# /addons/sshfs_mount/Dockerfile
ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install dependencies: sshfs (for FUSE), samba (to re-share), and sshpass (for password auth)
RUN apk add --no-cache \
    openssh-client \
    sshfs \
    samba \
    sshpass

# Copy the run script and smb.conf template
COPY run.sh /
COPY smb.conf.template /

# Make the run script executable
RUN chmod a+x /run.sh
RUN chmod a+x /smb.conf.template

# Expose Samba port internally (no host binding)
EXPOSE 445

CMD [ "/run.sh" ]
