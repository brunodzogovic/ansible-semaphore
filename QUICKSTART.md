# Quickstart

This guide covers the initial deployment and activation of automatic stable Semaphore updates on the Docker host running the Compose stack.

## 1. Prerequisites

The host must provide:

```text
Docker Engine
Docker Compose v2
Python 3
curl
flock
cron/crontab
Git
```

Confirm the main commands are available:

```bash
docker --version
docker compose version
python3 --version
curl --version
flock --version
crontab -l >/dev/null 2>&1 || true
```

The user performing the installation must be able to run Docker without an interactive password prompt.

## 2. Clone or update the repository

For a new installation:

```bash
git clone https://github.com/brunodzogovic/ansible-semaphore.git
cd ansible-semaphore
```

For an existing installation:

```bash
cd /path/to/ansible-semaphore
git pull
```

Until the automation pull request is merged, use the implementation branch:

```bash
git fetch origin
git switch feature/automated-semaphore-updates
git pull --ff-only
```

After it is merged, switch back to `main`:

```bash
git switch main
git pull --ff-only
```

## 3. Configure `.env`

Create or update the local `.env` file. It is intentionally excluded from Git.

At minimum, verify these image settings:

```dotenv
SEMAPHORE_VERSION=2.18.9
DOCKER_REPOSITORY_NAME=brunodzogovic
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

For a private or self-hosted registry, include its hostname and namespace:

```dotenv
DOCKER_REPOSITORY_NAME=registry.example.com/cloud-images
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

Also configure the normal Semaphore and database variables used by `compose.yaml`:

```dotenv
DB_USER=semaphore
DB_PASS=replace-me
DB_HOST=mysql
DB_PORT=3306
DB_DIALECT=mysql
SEMAPHORE_DB=semaphore

SEMAPHORE_ADMIN=admin
SEMAPHORE_ADMIN_NAME=Administrator
SEMAPHORE_ADMIN_EMAIL=admin@example.com
SEMAPHORE_ADMIN_PASSWORD=replace-me
SEMAPHORE_ACCESS_KEY_ENCRYPTION=replace-with-a-strong-value
```

Do not commit the real `.env` file.

## 4. Authenticate to the image registry

The automatic updater pushes the new image before refreshing the deployment. Authenticate the Docker host to the registry configured in `.env`.

Example:

```bash
docker login
```

For a registry with an explicit hostname:

```bash
docker login registry.example.com
```

Verify that the configured account can push to:

```text
${DOCKER_REPOSITORY_NAME}/${CUSTOM_IMAGE_NAME}
```

## 5. Validate the Compose configuration

```bash
docker compose --env-file .env config >/dev/null
```

No output and a zero exit status indicate successful interpolation and validation.

The external Docker network named `ingress` must already exist:

```bash
docker network inspect ingress >/dev/null 2>&1 || docker network create ingress
```

## 6. Perform the initial deployment

Build the configured Semaphore version:

```bash
docker compose --env-file .env build semaphore-kubespray
```

Push the image:

```bash
docker compose --env-file .env push semaphore-kubespray
```

Start the complete stack:

```bash
docker compose --env-file .env up -d
```

Check its state:

```bash
docker compose --env-file .env ps
curl --fail http://127.0.0.1:3000/ >/dev/null
```

Inspect logs when needed:

```bash
docker compose --env-file .env logs --tail=100 semaphore-kubespray
```

## 7. Test stable-release detection

Check the latest stable Semaphore release without modifying `.env`:

```bash
python3 latest-version.py .env --check-only
```

The detector ignores releases marked by GitHub as:

```text
draft
prerelease
```

This excludes beta, release-candidate, and other prerelease builds when upstream marks them correctly.

## 8. Test the complete updater manually

Run the updater interactively before enabling cron:

```bash
bash scripts/update-semaphore.sh
```

Expected behavior when no update exists:

```text
The script reports that Semaphore is already current.
No image is built.
No container is restarted.
```

Expected behavior when a stable update exists:

```text
.env is backed up and updated.
A pre-upgrade MySQL dump is created when MySQL is running.
The new image is built and pushed.
The Semaphore service is recreated.
The HTTP endpoint is checked.
The previous local image is removed after success.
```

Check the result:

```bash
grep '^SEMAPHORE_VERSION=' .env
docker compose --env-file .env ps
docker images "$(awk -F= '/^DOCKER_REPOSITORY_NAME=/{r=$2} /^CUSTOM_IMAGE_NAME=/{i=$2} END{print r "/" i}' .env)"
```

Review backups:

```bash
ls -lh backups/ 2>/dev/null || true
```

### Reverse-proxy health check

The default check uses:

```text
http://127.0.0.1:3000/
```

To test through the Eclipse Cloud reverse proxy instead:

```bash
SEMAPHORE_HEALTH_URL=https://ansible.internal.eclipse.tele.no/ \
  bash scripts/update-semaphore.sh
```

Only use the reverse-proxy URL when the cron-running host trusts its certificate and can resolve the hostname.

## 9. Enable the daily cron check

Install the default daily schedule at 03:17 local time:

```bash
bash scripts/install-update-cron.sh
```

Confirm the installed entry:

```bash
crontab -l
```

Monitor the updater log:

```bash
tail -f logs/semaphore-update.log
```

Use another schedule when required:

```bash
bash scripts/install-update-cron.sh --schedule '17 4 * * *'
```

Remove automatic updates:

```bash
bash scripts/install-update-cron.sh --remove
```

## 10. Rollback and recovery

The updater automatically restores the previous `.env` and recreates the previous Semaphore image when build, push, deployment, or health verification fails.

Relevant retained files are:

```text
.env.bak
backups/semaphore-db-<timestamp>-before-<version>.sql
logs/semaphore-update.log
```

Manual application rollback:

```bash
cp .env.bak .env
docker compose --env-file .env up -d --no-deps --force-recreate semaphore-kubespray
```

Check logs afterward:

```bash
docker compose --env-file .env logs --tail=200 semaphore-kubespray
```

A previous application image may not be compatible with a database that has already completed a newer migration. When database recovery is required, stop Semaphore and restore the retained SQL dump using the normal MySQL recovery procedure before restarting the old image.

## 11. What cleanup currently does

After a successful update, the updater removes only the previous version-tagged image from the local Docker host.

It does not delete old image versions from the remote registry. Configure registry-native retention separately until registry-specific cleanup is implemented.

It also does not run broad cleanup commands such as:

```text
docker system prune -a
```

This is deliberate because the Seed host runs other services.

## Operational checklist

Before enabling cron, confirm all of the following:

- [ ] `.env` contains the correct image repository and runtime settings.
- [ ] The Docker host is authenticated to the registry.
- [ ] `docker compose --env-file .env config` succeeds.
- [ ] The `ingress` Docker network exists.
- [ ] The current stack starts successfully.
- [ ] `latest-version.py --check-only` succeeds.
- [ ] `scripts/update-semaphore.sh` has been run manually.
- [ ] The database backup directory is writable.
- [ ] The health endpoint succeeds from the host.
- [ ] The cron-running user can run Docker non-interactively.
- [ ] `logs/semaphore-update.log` is monitored after enabling cron.
