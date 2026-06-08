# Ansible Semaphore with Kubespray tooling

Docker Compose deployment of Semaphore UI backed by MySQL. The custom image includes Ansible dependencies used by Kubespray and the OpenTofu CLI.

For first-time installation and rollout, see [QUICKSTART.md](QUICKSTART.md).

## Current implementation status

The repository now includes a complete host-side update mechanism for Semaphore:

- stable release discovery from the official Semaphore GitHub Releases API;
- explicit exclusion of draft, beta, release-candidate, and other prerelease versions;
- automatic update of `SEMAPHORE_VERSION` in the local `.env` file;
- image build using the updated version;
- image push to the repository configured in `.env`;
- pre-upgrade MySQL backup when the bundled MySQL service is running;
- recreation of only the `semaphore-kubespray` service;
- HTTP and container-state health verification after deployment;
- rollback to the previous `.env` and previous image when an update fails;
- removal of the superseded image from the local Docker host after a successful update;
- optional daily cron installation;
- validation of shell scripts, Python, and Compose configuration through GitHub Actions.

The automation is implemented in:

```text
latest-version.py
scripts/update-semaphore.sh
scripts/install-update-cron.sh
.github/workflows/validate.yml
```

Remote registry cleanup is not automated yet. Registry deletion APIs differ between Docker Hub, GHCR, Harbor, and other registries. The current implementation removes only the old local image after the new deployment is verified.

## Local configuration

The deployment is configured through `.env`. Keep the real `.env` local; it is excluded by `.gitignore`. The distributed/default file is intended as a template showing which values must be configured.

The automatic updater requires at least:

```dotenv
SEMAPHORE_VERSION=2.18.9
DOCKER_REPOSITORY_NAME=[docker-repo-name]
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

`DOCKER_REPOSITORY_NAME` may also contain a registry hostname and namespace, for example:

```dotenv
DOCKER_REPOSITORY_NAME=registry.example.com/cloud-images
CUSTOM_IMAGE_NAME=semaphore-kubespray
```

The resulting image reference is:

```text
${DOCKER_REPOSITORY_NAME}/${CUSTOM_IMAGE_NAME}:${SEMAPHORE_VERSION}
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

1. Acquires a lock with `flock` to prevent overlapping runs.
2. Records the current version and image reference.
3. Updates `SEMAPHORE_VERSION` in `.env`.
4. Creates a MySQL dump under `backups/` when the Compose MySQL service is running.
5. Builds the new version-tagged image.
6. Pushes it to `${DOCKER_REPOSITORY_NAME}/${CUSTOM_IMAGE_NAME}`.
7. Recreates only the `semaphore-kubespray` service.
8. Verifies that the container is running and that the Semaphore HTTP endpoint responds.
9. Removes the superseded image tag from the local Docker host.

When no new stable version is available, the script exits successfully without rebuilding or restarting anything.

If version lookup, backup, build, push, deployment, or health verification fails, the script restores the previous `.env` and recreates the previous Semaphore service. The pre-upgrade database dump is retained for manual recovery.

The default health endpoint is:

```text
http://127.0.0.1:3000/
```

It can be overridden when Semaphore is checked through the reverse proxy:

```bash
SEMAPHORE_HEALTH_URL=https://ansible.internal.eclipse.tele.no/ \
  bash scripts/update-semaphore.sh
```

Other optional runtime overrides include:

```bash
ENV_FILE=/path/to/.env
BACKUP_DIR=/path/to/backups
LOCK_FILE=/run/lock/semaphore-kubespray-update.lock
SEMAPHORE_HEALTH_RETRIES=12
SEMAPHORE_HEALTH_RETRY_DELAY=5
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

Updater output is written to:

```text
logs/semaphore-update.log
```

The cron entry runs as the user who installs it. That user must:

- be able to run Docker without an interactive password prompt;
- have Docker Compose v2 available;
- have `python3`, `curl`, `flock`, and `cron` installed;
- already be authenticated to the configured image registry;
- have network access to GitHub's API and the configured registry.

## Recovery and retained artifacts

The updater may create:

```text
.env.bak
backups/semaphore-db-<timestamp>-before-<version>.sql
logs/semaphore-update.log
```

These files are excluded from Git.

If a database migration succeeds but the application subsequently fails, restoring the previous image may not be enough. Use the retained SQL dump for manual database recovery when required.

## Validation

The repository workflow validates:

```text
bash syntax
Python syntax
Docker Compose interpolation and structure
```

It does not perform a full image build or production deployment. The first execution on the Seed host must therefore be performed manually and reviewed before cron is enabled.
