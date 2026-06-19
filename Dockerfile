# Build from Debian based Python image
FROM ghcr.io/opentofu/opentofu:minimal AS tofu
FROM python:3.13.1-slim-bullseye

ARG SEMAPHORE_VERSION
ARG KUBESPRAY_REF=v2.31.0

ENV SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore \
    KUBESPRAY_DIR=/opt/kubespray \
    KUBESPRAY_REF=${KUBESPRAY_REF} \
    KUBESPRAY_VERSION_FILE=/opt/kubespray/.eclipse-kubespray-version \
    TZ=UTC

# Install required packages
COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        wget \
        gettext \
        curl \
        gnupg \
        ca-certificates \
        lsb-release \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Embed the exact Kubespray release selected by Compose/.env into the image.
RUN test -n "${KUBESPRAY_REF}" \
    && git clone --depth 1 --branch "${KUBESPRAY_REF}" https://github.com/kubernetes-sigs/kubespray "${KUBESPRAY_DIR}" \
    && printf '%s\n' "${KUBESPRAY_REF}" > "${KUBESPRAY_VERSION_FILE}" \
    && test "$(git -C "${KUBESPRAY_DIR}" describe --tags --always)" = "${KUBESPRAY_REF}"

COPY requirements.txt /tmp/semaphore-requirements.txt

RUN cd "${KUBESPRAY_DIR}" \
    && pip install --no-cache-dir -U -r requirements.txt \
    && pip install --no-cache-dir -U -r /tmp/semaphore-requirements.txt

# Download and install Semaphore
RUN test -n "${SEMAPHORE_VERSION}" \
    && cd /tmp \
    && wget -q "https://github.com/semaphoreui/semaphore/releases/download/v${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.deb" \
    && dpkg -i "/tmp/semaphore_${SEMAPHORE_VERSION}_linux_amd64.deb" \
    && rm -f "/tmp/semaphore_${SEMAPHORE_VERSION}_linux_amd64.deb"

# Copy Semaphore configuration
COPY config_template.json /semaphore/config_template.json
COPY entrypoint.sh /semaphore/entrypoint.sh
RUN chmod +x /semaphore/entrypoint.sh

# Install Ansible requirements
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
    && rm -rf /tmp/requirements.yml /tmp/semaphore-requirements.txt

ENTRYPOINT ["/semaphore/entrypoint.sh"]