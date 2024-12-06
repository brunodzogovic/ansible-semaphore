# Build from Debian based Python image
FROM python:3.13.0b2-slim-bookworm

# Set default env variables
ENV SEMAPHORE_DB_USER=semaphore
ENV SEMAPHORE_DB_PASS=semaphore
ENV SEMAPHORE_DB_HOST=mysql
ENV SEMAPHORE_DB_PORT=3306
ENV SEMAPHORE_DB_DIALECT=mysql
ENV SEMAPHORE_DB=semaphore
ENV SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
ENV SEMAPHORE_ADMIN_PASSWORD=changeme
ENV SEMAPHORE_ADMIN_NAME=admin
ENV SEMAPHORE_ADMIN_EMAIL=admin@localhost
ENV SEMAPHORE_ADMIN=admin
ENV SEMAPHORE_ACCESS_KEY_ENCRYPTION=gs72mPntFATGJs9qK0pQ0rKtfidlexiMjYCH9gWKhTU=
ENV SEMAPHORE_LDAP_PORT: '636'
ENV SEMAPHORE_LDAP_NEEDTLS: 'yes'
ENV SEMAPHORE_LDAP_DN_BIND: 'uid=bind_user,cn=users,cn=accounts,dc=local,dc=shiftsystems,dc=net'
ENV SEMAPHORE_LDAP_PASSWORD: 'ldap_bind_account_password'
ENV SEMAPHORE_LDAP_DN_SEARCH: 'dc=local,dc=example,dc=com'
ENV SEMAPHORE_LDAP_SEARCH_FILTER: "(\u0026(uid=%s)(memberOf=cn=ipausers,cn=groups,cn=accounts,dc=local,dc=example,dc=com))"
ENV TZ: UTC

# Install required packages
RUN apt-get -y update && apt-get -y install git wget gettext python3-pip
# Download and install semaphore
RUN pip3 install -U pip
RUN cd /tmp && wget https://github.com/semaphoreui/semaphore/releases/download/v2.10.7/semaphore_2.10.7_linux_amd64.deb
RUN dpkg -i /tmp/semaphore_2.10.7_linux_amd64.deb 
# Copy semaphore config
COPY config_template.json /semaphore/config_template.json
COPY entrypoint.sh /semaphore/entrypoint.sh
RUN chmod +x /semaphore/entrypoint.sh

# Clean up
RUN rm -rf /tmp/kubespray && rm -rf /tmp/semaphore_2.10.7_linux_amd64.deb
# Startup process
ENTRYPOINT ["/semaphore/entrypoint.sh"]
