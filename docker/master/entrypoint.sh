#!/bin/sh
set -e

buildbot upgrade-master .

# buildbot.tac logs to twistd.log; copy it to stdout for the container
# log.
touch twistd.log
tail -n +1 -F twistd.log &

exec twistd --nodaemon --pidfile= --python=buildbot.tac
