FROM alpine

COPY /bin /provisioner

ENTRYPOINT "/provisioner/start-cmd.sh" && /bin/sh
