#!/bin/bash
set -e
container=docker
export container

if [ $# -eq 0 ]; then
	echo >&2 'ERROR: No command specified. You probably want to run `journalctl -f`, or maybe `bash`?'
	exit 1
fi

#if [ ! -t 0 ]; then
#	echo >&2 'ERROR: TTY needs to be enabled (`docker run -t ...`).'
#	exit 1
#fi

# remove ubuntu user
userdel -r ubuntu > /dev/null 2>&1

# create additional groups
_IFS=${IFS}; IFS=,
for gid in ${USER_GROUPS?}; do
	if ! getent group "${gid:?}" > /dev/null 2>&1; then
		groupadd --gid "${gid:?}" "g_${gid:?}"
	fi
done
IFS=$_IFS

# create user and group
if ! getent group "${USER_GID:?}" > /dev/null 2>&1; then
	groupadd --gid "${USER_GID:?}" "${USER_NAME:?}"
fi
if ! getent passwd "${USER_UID:?}" > /dev/null 2>&1; then
	useradd \
		--uid "${USER_UID:?}" \
		--gid "${USER_GID:?}" \
		--groups "${USER_GROUPS?}" \
		--shell "${USER_SHELL:?}" \
		--home-dir "${USER_HOME:?}" \
		--create-home \
		"${USER_NAME:?}"
fi

# set user password
if [ -n "${USER_PASSWORD?}" ]; then
	printf '%s' "${USER_NAME:?}:${USER_PASSWORD:?}" | chpasswd
else
	passwd -d "${USER_NAME:?}"
fi

if [ -w "${USER_HOME:?}" ]; then
	# copy /etc/skel/ to user home if certain files do not exist
	if [ ! -e "${USER_HOME:?}"/.profile ]; then
		cp -aT /etc/skel/ "${USER_HOME:?}" ||:
		find /etc/skel/ -mindepth 1 -exec sh -c 'chown "$1:" "$2/${3#/etc/skel/}"' _ "${USER_NAME:?}" "${USER_HOME:?}" '{}' ';'
	fi

	# set user home permissions
	if [ "$(stat -c '%u' "${USER_HOME:?}")" != "${USER_UID:?}" ]; then
		chown "${USER_NAME:?}:" "${USER_HOME:?}"
	fi
	if [ "$(stat -c '%a' "${USER_HOME:?}")" != '750' ]; then
		chmod 750 "${USER_HOME:?}"
	fi
fi

# create /run/user/${USER_UID}/ directory if it does not exist
if [ ! -d /run/user/"${USER_UID:?}"/ ]; then
	mkdir -p /run/user/"${USER_UID:?}"/
	chmod 700 /run/user/"${USER_UID:?}"/
	chown "${USER_NAME:?}:" /run/user/"${USER_UID:?}"/
fi

# disable glx module if /dev/dri/ does not exist
if [ ! -d /dev/dri/ ]; then
	printf '%s\n' '"/dev/dri/" does not exist, glx module will be disabled' 1>&2
	sed -i 's|Load \("glx"\)|Disable \1|g' /etc/X11/xrdp/xorg.conf
fi

# start systemd with container workarounds
env >/etc/container-entrypoint-env

cat >/etc/systemd/system/container-entrypoint.target <<EOF
[Unit]
Description=the target for container-entrypoint.service
Requires=container-entrypoint.service systemd-logind.service systemd-user-sessions.service
EOF

quoted_args="$(printf " %q" "${@}")"
echo "${quoted_args}" >/etc/container-entrypoint-cmd

cat >/etc/systemd/system/container-entrypoint.service <<EOF
[Unit]
Description=container-entrypoint.service

[Service]
ExecStart=/bin/bash -exc "source /etc/container-entrypoint-cmd"
# EXIT_STATUS is either an exit code integer or a signal name string, see systemd.exec(5)
ExecStopPost=/bin/bash -ec "if echo \${EXIT_STATUS} | grep [A-Z] > /dev/null; then echo >&2 \"got signal \${EXIT_STATUS}\"; systemctl exit \$(( 128 + \$( kill -l \${EXIT_STATUS} ) )); else systemctl exit \${EXIT_STATUS}; fi"
StandardInput=tty-force
StandardOutput=inherit
StandardError=inherit
WorkingDirectory=$(pwd)
EnvironmentFile=/etc/container-entrypoint-env

[Install]
WantedBy=multi-user.target
EOF

systemctl mask systemd-firstboot.service systemd-udevd.service systemd-modules-load.service proc-sys-fs-binfmt_misc.automount sys-kernel-config.mount sys-kernel-debug.mount sys-kernel-tracing.mount >/dev/null 2>&1
systemctl unmask systemd-logind >/dev/null 2>&1
systemctl enable container-entrypoint.service >/dev/null 2>&1

systemd=
if [ -x /lib/systemd/systemd ]; then
	systemd=/lib/systemd/systemd
elif [ -x /usr/lib/systemd/systemd ]; then
	systemd=/usr/lib/systemd/systemd
elif [ -x /sbin/init ]; then
	systemd=/sbin/init
else
	echo >&2 'ERROR: systemd is not installed'
	exit 1
fi

# Workaround for https://github.com/systemd/systemd/issues/37709:
# Docker bind-mounts the PTY slave to /dev/console, but newer systemd (258+)
# requires /dev/console to be a symlink to the PTY device. Replace if needed.
# This replicates the fix from containers/crun#1796 for Docker-based runtimes.
if mountpoint -q /dev/console 2>/dev/null; then
    _mi=$(awk '$5=="/dev/console" {print $3,$4; exit}' /proc/self/mountinfo 2>/dev/null)
    read -r _devno _root <<< "$_mi"
    if [ -n "$_devno" ]; then
        _pts_mnt=$(awk -v devno="$_devno" '$3==devno && $4=="/" {print $5; exit}' /proc/self/mountinfo 2>/dev/null)
        if [ -n "$_pts_mnt" ]; then
            _ptynum="${_root#/}"
            _pty="${_pts_mnt}/${_ptynum}"
            if [ -c "$_pty" ]; then
                umount /dev/console 2>/dev/null && ln -sf "$_pty" /dev/console 2>/dev/null || true
            fi
        fi
    fi
    unset _mi _devno _root _pts_mnt _ptynum _pty
fi

systemd_args="${ARGS} --show-status=false --unit=container-entrypoint.target"
echo "$0: starting $systemd $systemd_args"
set -ex
exec $systemd $systemd_args
