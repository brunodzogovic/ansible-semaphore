# Quickstart

This guide covers the minimum steps required after pulling the repository.

## 1. Pull the repository

For a new installation:

```bash
git clone https://github.com/brunodzogovic/ansible-semaphore.git
cd ansible-semaphore
```

For an existing installation:

```bash
cd /path/to/ansible-semaphore
git pull --ff-only
```

Until the automation pull request is merged, use the implementation branch:

```bash
git fetch origin
git switch feature/automated-semaphore-updates
git pull --ff-only
```

## 2. Update `.env`

Create or edit the local `.env` file and set the required image, database, and Semaphore values.

At minimum, verify:

```dotenv
SEMAPHORE_VERSION=2.18.9
DOCKER_REPOSITORY_NAME=brunodzogovic
CUSTOM_IMAGE_NAME=semaphore-kubespray

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

For another registry, include its hostname and namespace in `DOCKER_REPOSITORY_NAME`:

```dotenv
DOCKER_REPOSITORY_NAME=registry.example.com/cloud-images
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

Authenticate Docker to the configured registry before continuing:

```bash
docker login
```

Or:

```bash
docker login registry.example.com
```

## 3. Start the deployment

Ensure that the required external Docker network exists:

```bash
docker network inspect ingress >/dev/null 2>&1 || docker network create ingress
```

Validate the Compose configuration:

```bash
docker compose --env-file .env config >/dev/null
```

Build, push, and start the stack:

```bash
docker compose --env-file .env build semaphore-kubespray
docker compose --env-file .env push semaphore-kubespray
docker compose --env-file .env up -d
```

Check the deployment:

```bash
docker compose --env-file .env ps
curl --fail http://127.0.0.1:3000/ >/dev/null
```

Semaphore is available directly on:

```text
http://<host-address>:3000/
```

## 4. Test the updater

Check for the latest stable Semaphore release without changing `.env`:

```bash
python3 latest-version.py .env --check-only
```

Run the complete update workflow manually:

```bash
bash scripts/update-semaphore.sh
```

When no new stable release exists, the script exits without rebuilding or restarting the deployment.

When a new stable release exists, the script updates `.env`, creates a database backup, builds and pushes the new image, refreshes Semaphore, verifies port `3000`, and removes the old local image after success.

## 5. Enable automatic checks

Install the default daily cron check:

```bash
bash scripts/install-update-cron.sh
```

Confirm it:

```bash
crontab -l
```

Updater output is written to:

```text
logs/semaphore-update.log
```

Use another schedule when required:

```bash
bash scripts/install-update-cron.sh --schedule '17 4 * * *'
```

Remove the cron entry:

```bash
bash scripts/install-update-cron.sh --remove
```
