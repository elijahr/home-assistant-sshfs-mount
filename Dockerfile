# /addons/sshfs_mount/Dockerfile
ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install dependencies
RUN apk add --no-cache \
    openssh-client \
    openssh-server \
    sshfs \
    samba \
    sshpass \
    inotify-tools

# Copy rootfs with s6-overlay services and scripts
COPY rootfs /

# Expose Samba port internally (no host binding)
EXPOSE 445
