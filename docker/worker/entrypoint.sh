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

# Use buildbot-worker start rather than twistd directly: it puts the
# worker directory on sys.path, which the settings import in
# buildbot.tac depends on.
exec buildbot-worker start --nodaemon .
