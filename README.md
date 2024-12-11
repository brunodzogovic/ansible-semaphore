# Ansible Semaphore
Docker Compose based backend deployment of Ansible Semaphore UI and a database. Deploys Semaphore with default credentials (insecure) by running `docker compose up -d`. This particular Semaphore version is configured to support running Kubespray Ansible playbooks for automated deployment of Kubernetes clusters.

A Dockerfile is created to help building your own image with the parameters outlined. There's a JSON config file which helps with pre-configuring the Semaphore UI during the buld stage. An entrypoint script is used to set the proper credentials based on the env variables. Last but not least, a Compose file for deploying the Semaphore backend. In the current version, the public image of Semaphore is selected. This should be changed in the Compose file to correspond to your own built image.

The credentials are set to defaults in the Dockerfile and should be adjusted accordingly. Do not forget to add these in a .gitignore and/or use vault to secure the secrets.

There's two options for running the Semaphore UI: With a Postgres DB or MySQL. This can be set by commenting/uncommenting accordingly in the ``compose.yml`` file.
