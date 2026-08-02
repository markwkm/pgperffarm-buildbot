#!/bin/sh
# Build the images, start the compose environment, wait for the
# workers to connect, and run every test script.  Expect several
# PostgreSQL builds' worth of run time.  Run from the top of this
# repository.
set -e

# shellcheck source=docker/testlib.sh
. ./docker/testlib.sh

WORKERS_EXPECTED="${WORKERS_EXPECTED:-2}"

docker compose up -d --build

echo "waiting for ${WORKERS_EXPECTED} workers to connect"
SECONDS_WAITED=0
while :; do
	CONNECTED="$(curl -s "${BUILDBOTURL}/api/v2/workers" \
			2> /dev/null | python3 -c "
import json, sys
workers = json.load(sys.stdin)['workers']
print(sum(1 for w in workers if w['connected_to']))" \
			2> /dev/null || echo 0)"
	if [ "${CONNECTED}" -ge "${WORKERS_EXPECTED}" ]; then
		break
	fi
	if [ "${SECONDS_WAITED}" -ge 300 ]; then
		echo "FAIL: workers did not connect"
		exit 1
	fi
	sleep 5
	SECONDS_WAITED=$(( SECONDS_WAITED + 5 ))
done
echo "workers connected"

sh docker/test-force.sh
sh docker/test-patch.sh
sh docker/test-try.sh
sh docker/test-poller.sh

# The poller test only asserts that a build was triggered; wait for
# it, and anything else still queued, to finish successfully.
echo "waiting for remaining builds to finish"
wait_quiet
echo "PASS: all tests completed"
