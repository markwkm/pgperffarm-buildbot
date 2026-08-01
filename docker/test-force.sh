#!/bin/sh
# Force dbt2 builds of specific PostgreSQL revisions: the pinned
# baseline commit on worker1 and the poller test's src/ commit on
# worker2, in parallel.  Wait for both builds and verify each checked
# out the requested revision by comparing the got_revision property,
# which also exercises the source step ordering that keeps the
# PostgreSQL revision in got_revision.  Run from the top of this
# repository while the compose environment is up.
set -e

BUILDBOTURL="${BUILDBOTURL:-http://localhost:8010}"
BUILDBOT_USER="${BUILDBOT_USER:-admin@example.com}"
BUILDBOT_PASSWORD="${BUILDBOT_PASSWORD:-admin}"
# Seconds to wait for each build to finish.
BUILDWAIT="${BUILDWAIT:-3600}"

# shellcheck source=docker/fixture.sh
. ./docker/fixture.sh

COOKIES="$(mktemp)"
trap 'rm -f "${COOKIES}"' EXIT

curl -s -c "${COOKIES}" \
		-u "${BUILDBOT_USER}:${BUILDBOT_PASSWORD}" \
		"${BUILDBOTURL}/auth/login" > /dev/null

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

# Wait for the build claiming a build request to finish and verify it
# built the wanted revision.
wait_build()
{
	BRID="${1}"
	WANTED="${2}"

	BUILDID=""
	SECONDS_WAITED=0
	while [ -z "${BUILDID}" ]; do
		if [ "${SECONDS_WAITED}" -ge 120 ]; then
			echo "FAIL: no build started for request ${BRID}"
			exit 1
		fi
		sleep 5
		SECONDS_WAITED=$(( SECONDS_WAITED + 5 ))
		BUILDID="$(curl -s \
				"${BUILDBOTURL}/api/v2/buildrequests/${BRID}/builds" \
				| python3 -c \
				"import json, sys
builds = json.load(sys.stdin)['builds']
print(builds[-1]['buildid'] if builds else '')")"
	done

	SECONDS_WAITED=0
	while [ "${SECONDS_WAITED}" -lt "${BUILDWAIT}" ]; do
		STATE="$(curl -s "${BUILDBOTURL}/api/v2/builds/${BUILDID}" \
				| python3 -c \
				"import json, sys
build = json.load(sys.stdin)['builds'][0]
print('done', build['results']) if build['complete'] \
    else print('building')")"
		if [ "${STATE}" != "building" ]; then
			break
		fi
		sleep 30
		SECONDS_WAITED=$(( SECONDS_WAITED + 30 ))
	done
	if [ "${STATE}" = "building" ]; then
		echo "FAIL: build ${BUILDID} did not finish in ${BUILDWAIT}s"
		exit 1
	fi

	RESULTS="${STATE#done }"
	if [ "${RESULTS}" -gt 1 ]; then
		echo "FAIL: build ${BUILDID} finished with results ${RESULTS}"
		exit 1
	fi

	GOT="$(curl -s "${BUILDBOTURL}/api/v2/builds/${BUILDID}/properties" \
			| python3 -c \
			"import json, sys
properties = json.load(sys.stdin)['properties'][0]
print(properties.get('got_revision', ['?'])[0])")"
	if [ "${GOT}" != "${WANTED}" ]; then
		echo "FAIL: build ${BUILDID} got_revision ${GOT}," \
				"wanted ${WANTED}"
		exit 1
	fi
	echo "PASS: build ${BUILDID} built revision ${WANTED}"
}

echo "forcing baseline ${BASELINE} on worker1"
BRID1="$(force worker1 "${BASELINE}")"
echo "forcing src/ commit ${COMMIT_SRC} on worker2"
BRID2="$(force worker2 "${COMMIT_SRC}")"

wait_build "${BRID1}" "${BASELINE}"
wait_build "${BRID2}" "${COMMIT_SRC}"
echo "PASS: forced revision builds completed"
