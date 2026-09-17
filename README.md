## systemd Ubuntu Xfce xrdp container

A container image based on Ubuntu 26.04 with systemd, the Xfce desktop environment, pipewire audio, and xrdp.

This container runs [privileged](https://docs.podman.io/en/v4.3/markdown/options/privileged.html) with the same permissions on the host as the user that runs it. This is so it can mount the cgroup virtual file system with read-write permissions. It is recommended to run priviledged containers rootless. See [Docker rootless](https://docs.docker.com/engine/security/rootless/) and [Podman Desktop rootless](https://podman-desktop.io/docs/podman/setting-podman-machine-default-connection).

### Start an instance with compose

```shell
git clone https://github.com/isklinger/container-image-systemd-ubuntu-xrdp
cp container-image-systemd-ubuntu-xrdp/compose.sample.yml compose.yml
# keep or change the default values of the environment variables as applicable
# optionally, mount a path on the host as the user home directory for persistance
```

```yaml
services:
  ubuntu-xrdp:
    build:
      context: container-image-systemd-ubuntu-xrdp
      dockerfile: Containerfile
    container_name: ubuntu-xrdp
    hostname: ubuntu-xrdp
    shm_size: '2gb'
    privileged: true
    cgroup: host
    tty: true
    ports:
      - '52222:22/tcp'
      - '53322:3322/tcp'
      - '53389:3389/tcp'
    tmpfs:
      - /tmp
      - /run
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - USER_NAME=user
      - USER_PASSWORD=password
      - USER_GROUPS=sudo
      - USER_SHELL=/bin/bash
      - USER_HOME=/home/user
#    volumes:
#      - ./user:/home/user
    command: /bin/bash -c "
      systemctl start sshd &&
      systemctl start xrdp &&
      read
      "
```

```shell
podman compose up
# or
docker compose up
```

### Environment variables and credentials

* `USER_UID`: user UID, default `1000`
* `USER_GID`: user GID, default `1000`
* `USER_NAME`: user name, default `user`
* `USER_PASSWORD`: user password, default `password`
* `USER_GROUPS`: comma-separated list of additional GIDs for the user, default `sudo`
* `USER_SHELL`: user shell, default `/bin/bash`

### Attribution

Copyright © Isaac Klinger

Based on the following container images:

https://github.com/hectorm/docker-xubuntu  
Copyright © Héctor Molinero Fernández  
MIT License

https://github.com/AkihiroSuda/containerized-systemd  
Copyright © Akihiro Suda  
Apache License 2.0

Builds with the firefox-deb-installer script  
https://github.com/StellarSand/firefox-deb-installer  
Copyright © StellarSand  
GPL v3.0 license
