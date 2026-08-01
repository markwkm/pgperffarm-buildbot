#!/bin/sh
# Force dbt2 builds of specific PostgreSQL revisions: the pinned
# baseline commit on worker1 and the poller test's src/ commit on
# worker2, in parallel.  Wait for both builds and verify each checked
# out the requested revision by comparing the got_revision property,
# which also exercises the source step ordering that keeps the
# PostgreSQL revision in got_revision.  Run from the top of this
# repository while the compose environment is up.
set -e

# shellcheck source=docker/testlib.sh
. ./docker/testlib.sh
# shellcheck source=docker/fixture.sh
. ./docker/fixture.sh

bb_login

# Queue a forced dbt2 build of a revision on a worker and print the
# resulting build request id.
force()
{
	curl -s -b "${COOKIES}" -H 'Content-Type: application/json' \
			--data @- \
			"${BUILDBOTURL}/api/v2/forceschedulers/run-dbt2-${1}" \
			<<EOF | python3 -c \
			"import json, sys
result = json.load(sys.stdin)['result']
print(list(result[1].values())[0])"
{"jsonrpc": "2.0", "method": "force", "id": 1, "params": {
    "reason": "forced revision test",
    "branch": "master",
    "revision": "${2}",
    "warehouses": 1,
    "duration": 60,
    "connection_delay": 1,
    "connections_per_processor": 1,
    "parallelism": 4,
    "terminal_limit": 4}}
EOF
}

echo "forcing baseline ${BASELINE} on worker1"
BRID1="$(force worker1 "${BASELINE}")"
echo "forcing src/ commit ${COMMIT_SRC} on worker2"
BRID2="$(force worker2 "${COMMIT_SRC}")"

wait_build "${BRID1}" "${BASELINE}"
wait_build "${BRID2}" "${COMMIT_SRC}"
echo "PASS: forced revision builds completed"
