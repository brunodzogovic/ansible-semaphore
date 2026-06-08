# Ansible Semaphore with Kubespray tooling

Docker Compose deployment of Semaphore UI backed by MySQL. The custom image includes Ansible dependencies used by Kubespray and the OpenTofu CLI.

## Local configuration

The deployment is configured through `.env`. Keep the real `.env` local; it is excluded by `.gitignore`. The distributed/default file is intended as a template showing which values must be configured.

The automatic updater requires at least:

```dotenv
SEMAPHORE_VERSION=2.18.9
DOCKER_REPOSITORY_NAME=brunodzogovic
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

`DOCKER_REPOSITORY_NAME` may also contain a registry hostname and namespace, for example:

```dotenv
DOCKER_REPOSITORY_NAME=registry.example.com/cloud-images
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

Authenticate the Docker host to that registry before enabling automatic updates.

## Manual deployment

```bash
docker compose --env-file .env build semaphore-kubespray
docker compose --env-file .env push semaphore-kubespray
docker compose --env-file .env up -d
```

## Stable release detection

`latest-version.py` reads Semaphore releases from the GitHub Releases API. Drafts and prereleases are explicitly ignored, so beta, release-candidate, and other prerelease builds are not selected.

Check the available version without modifying `.env`:

```bash
python3 latest-version.py .env --check-only
```

Update `SEMAPHORE_VERSION` in `.env`:

```bash
python3 latest-version.py .env
```

The previous file contents are saved as `.env.bak`.

## Automated update pipeline

Run the complete flow manually first:

```bash
bash scripts/update-semaphore.sh
```

When a newer stable release exists, the script:

1. Locks execution to prevent overlapping update runs.
2. Updates `SEMAPHORE_VERSION` in `.env`.
3. Creates a MySQL dump under `backups/` when the Compose MySQL service is running.
4. Builds the new image tag.
5. Pushes it to `${DOCKER_REPOSITORY_NAME}/${CUSTOM_IMAGE_NAME}`.
6. Recreates only the `semaphore-kubespray` service.
7. Verifies that the container is running and that the Semaphore HTTP endpoint responds.
8. Removes the superseded image tag from the local Docker host.

If build, push, deployment, or health verification fails, the script restores the previous `.env` and recreates the previous Semaphore service. The pre-upgrade database dump is retained for manual recovery.

The default health endpoint is `http://127.0.0.1:3000/`. It can be overridden when needed:

```bash
SEMAPHORE_HEALTH_URL=https://ansible.internal.eclipse.tele.no/ \
  bash scripts/update-semaphore.sh
```

## Cron installation

Install a daily check at 03:17 local time:

```bash
bash scripts/install-update-cron.sh
```

Use a different cron schedule:

```bash
bash scripts/install-update-cron.sh --schedule '17 4 * * *'
```

Remove the cron entry:

```bash
bash scripts/install-update-cron.sh --remove
```

Updater output is written to `logs/semaphore-update.log`.

The cron entry runs as the user who installs it. That user must be able to run Docker without an interactive password prompt and must already be authenticated to the configured image registry.
