#!/bin/sh
set -e

cat > settings.py <<EOF
"""
Generated from the container environment.
"""

BUILDMASTER_HOST = "${BUILDMASTER_HOST:-master}"
WORKERNAME = "${WORKER_NAME:?WORKER_NAME must be set}"
PASSWD = "${WORKER_PASSWORD:?WORKER_PASSWORD must be set}"
EOF

# buildbot.tac logs to twistd.log; copy it to stdout for the container
# log.
touch twistd.log
tail -n +1 -F twistd.log &

exec twistd --nodaemon --pidfile= --python=buildbot.tac
