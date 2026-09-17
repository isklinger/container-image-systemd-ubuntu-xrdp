ARG UBUNTU_VERSION="26.04"

FROM docker.io/ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

# systemd, xrdp, xorg, pipewire, xfce environment, and miscellaneous
RUN apt update
RUN apt install -y --no-install-recommends -o APT::Immediate-Configure=0 \
    dbus dbus-user-session systemd systemd-sysv \
    ca-certificates curl gnupg wget less avahi-daemon \
    openssh-client openssh-server \
    dialog fonts-liberation locales software-properties-common sudo zenity \
    pavucontrol pipewire-audio pipewire-module-xrdp pipewire-pulse pulseaudio-utils \
    mate-terminal xfce4 xfce4-indicator-plugin xfce4-notifyd xfce4-panel \
    xfce4-panel-profiles xfce4-pulseaudio-plugin xfce4-screenshooter \
    xfce4-taskmanager xfce4-whiskermenu-plugin \
    breeze-icon-theme greybird-gtk-theme xfce4-xkb-plugin console-data \
    xdg-user-dirs xdg-utils xorg xorgxrdp xrdp xvfb

RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# disable services that fail in container
RUN systemctl mask sys-kernel-debug.mount \
    sys-kernel-tracing.mount \
    sys-kernel-config.mount \
    proc-sys-fs-binfmt_misc.automount

# copy X11 and xrdp configuration and systemd services
COPY --chown=root:root ./etc/ /etc/
RUN <<-EOF
	find /etc/X11/xorg.conf.d/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
	find /etc/X11/xorg.conf.d/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'
EOF

COPY --chown=root:root ./opt/ /opt/
RUN <<-EOF
	find /opt/xrdp/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
	find /opt/xrdp/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'
EOF

# set credentials
ENV USER_UID=1000
ENV USER_GID=1000
ENV USER_NAME=user
ENV USER_PASSWORD=password
ENV USER_GROUPS=sudo
ENV USER_SHELL=/bin/bash
ENV USER_HOME=/home/user
RUN <<EOF
    mkdir -p /etc/sudoers.d
    echo '%sudo   ALL=(ALL:ALL) ALL' > /etc/sudoers.d/group_sudo
EOF

# set locale
RUN <<EOF
    echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
    echo 'LANG=en_US.UTF-8' > /etc/default/locale
    locale-gen
EOF

# entrypoint
COPY ./entrypoint/systemd-container-exec.sh /exec.sh
RUN <<EOF
    chmod og+x /exec.sh
EOF

ENTRYPOINT ["/exec.sh"]

# default ports
# SSH
EXPOSE 22/tcp
# RDP
EXPOSE 3389/tcp

# more packages - discretionary 
RUN mkdir -p /root/.gnupg
RUN curl -L https://raw.githubusercontent.com/StellarSand/firefox-deb-installer/refs/heads/main/install | bash
RUN apt update
RUN apt install -y --no-install-recommends -o APT::Immediate-Configure=0 \
    imagemagick \
    qalculate-gtk \
    vim \
    xclip \
    xdotool
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*
