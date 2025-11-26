# Build from Debian based Python image
FROM python:3.13.1-slim-bullseye

# Set default buildtime variables
ARG DB_USER
ARG DB_PASS
ARG DB_HOST
ARG DB_PORT
ARG DB_DIALECT
ARG SEMAPHORE_DB
ARG SEMAPHORE_ADMIN_PASSWORD
ARG SEMAPHORE_ADMIN_NAME
ARG SEMAPHORE_ADMIN
ARG SEMAPHORE_ACCESS_KEY_ENCRYPTION
ARG SEMAPHORE_LDAP_PASSWORD
ARG SEMAPHORE_VERSION

# Set default runtime variables
ENV SEMAPHORE_DB_USER=${DB_USER}
ENV SEMAPHORE_DB_PASS=${DB_PASS}
ENV SEMAPHORE_DB_HOST=${DB_HOST}
ENV SEMAPHORE_DB_PORT=${DB_PORT}
ENV SEMAPHORE_DB_DIALECT=${DB_DIALECT}
ENV SEMAPHORE_DB=${SEMAPHORE_DB}
ENV SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore
ENV SEMAPHORE_ADMIN_PASSWORD=${SEMAPHORE_ADMIN_PASSWORD}
ENV SEMAPHORE_ADMIN_NAME=${SEMAPHORE_ADMIN_NAME}
ENV SEMAPHORE_ADMIN_EMAIL=${SEMAPHORE_ADMIN_EMAIL}
ENV SEMAPHORE_ADMIN=${SEMAPHORE_ADMIN}
ENV SEMAPHORE_ACCESS_KEY_ENCRYPTION=${SEMAPHORE_ACCESS_KEY_ENCRYPTION}
ENV SEMAPHORE_LDAP_PORT: '636'
ENV SEMAPHORE_LDAP_NEEDTLS: 'yes'
ENV SEMAPHORE_LDAP_DN_BIND: 'uid=bind_user,cn=users,cn=accounts,dc=local,dc=shiftsystems,dc=net'
ENV SEMAPHORE_LDAP_PASSWORD: 'ldap_bind_account_password'
ENV SEMAPHORE_LDAP_DN_SEARCH: 'dc=local,dc=example,dc=com'
ENV SEMAPHORE_LDAP_SEARCH_FILTER: "(\u0026(uid=%s)(memberOf=cn=ipausers,cn=groups,cn=accounts,dc=local,dc=example,dc=com))"
ENV TZ: UTC

# Install required packages
RUN apt-get -y update && apt-get -y install git wget gettext
RUN git clone https://github.com/kubernetes-sigs/kubespray /tmp/kubespray
COPY requirements.txt /tmp/semaphore-requirements.txt
RUN cd /tmp/kubespray && pip install -U -r requirements.txt \
    && pip install -U -r /tmp/semaphore-requirements.txt
# Download and install semaphore
RUN cd /tmp && wget https://github.com/semaphoreui/semaphore/releases/download/v${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.deb 
RUN dpkg -i /tmp/semaphore_${SEMAPHORE_VERSION}_linux_amd64.deb 
# Copy semaphore config
COPY config_template.json /semaphore/config_template.json
COPY entrypoint.sh /semaphore/entrypoint.sh
RUN chmod +x /semaphore/entrypoint.sh

# Clean up
RUN rm -rf /tmp/kubespray && rm -rf /tmp/semaphore_${SEMAPHORE_VERSION}_amd64.deb
# Startup process
ENTRYPOINT ["/semaphore/entrypoint.sh"]
