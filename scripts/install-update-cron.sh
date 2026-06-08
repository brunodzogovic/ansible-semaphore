#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
UPDATE_SCRIPT="${REPO_DIR}/scripts/update-semaphore.sh"
LOG_DIR="${REPO_DIR}/logs"
LOG_FILE="${LOG_DIR}/semaphore-update.log"
DEFAULT_SCHEDULE="17 3 * * *"
SCHEDULE="${SEMAPHORE_UPDATE_CRON:-$DEFAULT_SCHEDULE}"
MARKER="# semaphore-kubespray-auto-update"

usage() {
    cat <<EOF
Usage:
  $0 [--schedule 'MIN HOUR DOM MON DOW']
  $0 --remove

Defaults to a daily check at 03:17 local time.
The schedule may also be supplied through SEMAPHORE_UPDATE_CRON.
EOF
}

mode="install"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --schedule)
            [[ $# -ge 2 ]] || { echo "Missing value for --schedule" >&2; exit 1; }
            SCHEDULE="$2"
            shift 2
            ;;
        --remove)
            mode="remove"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

command -v crontab >/dev/null 2>&1 || {
    echo "crontab is not installed. Install the cron package first." >&2
    exit 1
}

current_crontab="$(crontab -l 2>/dev/null || true)"
filtered_crontab="$(printf '%s\n' "$current_crontab" | grep -Fv "$MARKER" || true)"

if [[ "$mode" == "remove" ]]; then
    printf '%s\n' "$filtered_crontab" | sed '/^[[:space:]]*$/N;/^\n$/D' | crontab -
    echo "Removed the Semaphore automatic-update cron entry."
    exit 0
fi

[[ -f "$UPDATE_SCRIPT" ]] || {
    echo "Update script not found: $UPDATE_SCRIPT" >&2
    exit 1
}
[[ -f "${REPO_DIR}/.env" ]] || {
    echo "Environment file not found: ${REPO_DIR}/.env" >&2
    exit 1
}

mkdir -p "$LOG_DIR"
cron_command="cd $(printf '%q' "$REPO_DIR") && /usr/bin/env bash $(printf '%q' "$UPDATE_SCRIPT") >> $(printf '%q' "$LOG_FILE") 2>&1"
cron_line="${SCHEDULE} ${cron_command} ${MARKER}"

{
    printf '%s\n' "$filtered_crontab"
    printf '%s\n' "$cron_line"
} | awk 'NF || !blank { print; blank = !NF }' | crontab -

echo "Installed Semaphore update check with schedule: $SCHEDULE"
echo "Log file: $LOG_FILE"
echo "Run once manually with: bash $UPDATE_SCRIPT"
