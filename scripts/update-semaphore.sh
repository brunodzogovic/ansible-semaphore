#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_DIR}/.env}"
LOCK_FILE="${LOCK_FILE:-/tmp/semaphore-kubespray-update.lock}"
BACKUP_DIR="${BACKUP_DIR:-${REPO_DIR}/backups}"
SERVICE_NAME="${SEMAPHORE_SERVICE_NAME:-semaphore-kubespray}"
HTTP_URL="${SEMAPHORE_HEALTH_URL:-http://127.0.0.1:3000/}"
HTTP_RETRIES="${SEMAPHORE_HEALTH_RETRIES:-12}"
HTTP_RETRY_DELAY="${SEMAPHORE_HEALTH_RETRY_DELAY:-5}"

log() {
    printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

fail() {
    log "ERROR: $*"
    return 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

read_env_value() {
    local key="$1"
    local file="$2"
    awk -F= -v key="$key" '
        $0 ~ "^[[:space:]]*" key "=" {
            value = substr($0, index($0, "=") + 1)
            sub(/[[:space:]]+#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^['\"']|['\"']$/, "", value)
            print value
            exit
        }
    ' "$file"
}

wait_for_deployment() {
    local container_id
    container_id="$(docker compose --env-file "$ENV_FILE" ps -q "$SERVICE_NAME")"
    [[ -n "$container_id" ]] || return 1

    local attempt
    for ((attempt = 1; attempt <= HTTP_RETRIES; attempt++)); do
        if [[ "$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || true)" == "true" ]] \
            && curl --silent --show-error --fail --max-time 10 "$HTTP_URL" >/dev/null; then
            return 0
        fi
        sleep "$HTTP_RETRY_DELAY"
    done
    return 1
}

rollback() {
    local exit_code=$?
    trap - ERR
    log "Update failed; restoring the previous .env and deployment."
    cp -- "$ENV_ROLLBACK" "$ENV_FILE"
    docker compose --env-file "$ENV_FILE" up -d --no-deps --force-recreate "$SERVICE_NAME" || true
    rm -f -- "$ENV_ROLLBACK"
    exit "$exit_code"
}

require_command docker
require_command python3
require_command curl
require_command flock

[[ -f "$ENV_FILE" ]] || fail "Environment file not found: $ENV_FILE"
[[ -f "${REPO_DIR}/compose.yaml" ]] || fail "compose.yaml not found in $REPO_DIR"
[[ -x "${REPO_DIR}/latest-version.py" ]] || chmod +x "${REPO_DIR}/latest-version.py"

docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another Semaphore update is already running; exiting."
    exit 0
fi

cd "$REPO_DIR"

old_version="$(read_env_value SEMAPHORE_VERSION "$ENV_FILE")"
repository_name="$(read_env_value DOCKER_REPOSITORY_NAME "$ENV_FILE")"
custom_image_name="$(read_env_value CUSTOM_IMAGE_NAME "$ENV_FILE")"

[[ -n "$old_version" ]] || fail "SEMAPHORE_VERSION is missing from $ENV_FILE"
[[ -n "$repository_name" ]] || fail "DOCKER_REPOSITORY_NAME is missing from $ENV_FILE"
[[ -n "$custom_image_name" ]] || fail "CUSTOM_IMAGE_NAME is missing from $ENV_FILE"

image_repository="${repository_name%/}/${custom_image_name}"
old_image="${image_repository}:${old_version}"

ENV_ROLLBACK="$(mktemp "${ENV_FILE}.rollback.XXXXXX")"
cp -- "$ENV_FILE" "$ENV_ROLLBACK"
trap rollback ERR

log "Checking GitHub for the latest stable Semaphore release."
python3 "${REPO_DIR}/latest-version.py" "$ENV_FILE"

new_version="$(read_env_value SEMAPHORE_VERSION "$ENV_FILE")"
[[ -n "$new_version" ]] || fail "Updated SEMAPHORE_VERSION is empty"

if [[ "$new_version" == "$old_version" ]]; then
    log "No stable Semaphore update is available."
    rm -f -- "$ENV_ROLLBACK"
    trap - ERR
    exit 0
fi

new_image="${image_repository}:${new_version}"
log "Stable update detected: ${old_version} -> ${new_version}"

mkdir -p "$BACKUP_DIR"
backup_file="${BACKUP_DIR}/semaphore-db-$(date +%Y%m%d-%H%M%S)-before-${new_version}.sql"

if docker compose --env-file "$ENV_FILE" ps --status running mysql | grep -q mysql; then
    log "Creating a pre-upgrade database backup at $backup_file"
    docker compose --env-file "$ENV_FILE" exec -T mysql sh -ec \
        'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
        >"$backup_file"
else
    log "MySQL service is not running; skipping automatic database backup."
fi

log "Building ${new_image}"
docker compose --env-file "$ENV_FILE" build --pull "$SERVICE_NAME"

log "Pushing ${new_image}"
docker compose --env-file "$ENV_FILE" push "$SERVICE_NAME"

log "Refreshing the Semaphore deployment"
docker compose --env-file "$ENV_FILE" up -d --no-deps --force-recreate "$SERVICE_NAME"

if ! wait_for_deployment; then
    docker compose --env-file "$ENV_FILE" logs --tail=100 "$SERVICE_NAME" || true
    fail "The refreshed Semaphore deployment did not become healthy"
fi

log "Semaphore ${new_version} is running successfully."

if [[ "$old_image" != "$new_image" ]]; then
    log "Removing superseded local image ${old_image}"
    docker image rm "$old_image" >/dev/null 2>&1 || log "Old image was already absent or is still referenced; leaving it in place."
fi

rm -f -- "$ENV_ROLLBACK"
trap - ERR
log "Update completed successfully."
