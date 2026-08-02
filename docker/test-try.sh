#!/bin/sh
# Submit a patch with "buildbot try": create a file under src/ on top
# of a pinned PostgreSQL revision and run dbt2 on worker1 with it.
# Verify that the requested revision was checked out, that the source
# step applied the patch, and that the build read its parameters from
# the worker's test configuration like a polled build.  The try
# client runs inside the master container so nothing needs to be
# installed on the host.  Run from the top of this repository while
# the compose environment is up.
set -e

# shellcheck source=docker/testlib.sh
. ./docker/testlib.sh
# shellcheck source=docker/fixture.sh
. ./docker/fixture.sh

TRY_USER="${TRY_USER:-try}"
TRY_PASSWORD="${TRY_PASSWORD:-try}"

PATCHED_FILE="src/pgperffarm-try-test.txt"

cat > "${TESTTMP}/try.patch" <<EOF
--- /dev/null
+++ b/${PATCHED_FILE}
@@ -0,0 +1 @@
+created by the buildbot try test
EOF

REQUESTS0="$(count buildrequests)"

docker compose exec -T master sh -c 'cat > /tmp/try.patch' \
		< "${TESTTMP}/try.patch"

echo "submitting ${PATCHED_FILE} against ${COMMIT_SRC} with try"
docker compose exec -T master buildbot try \
		--connect=pb \
		--master=localhost:8031 \
		--username="${TRY_USER}" \
		--passwd="${TRY_PASSWORD}" \
		--who="docker test environment" \
		--branch=master \
		--baserev="${COMMIT_SRC}" \
		--diff=/tmp/try.patch \
		--patchlevel=1 \
		--builder=dbt2-worker1

SECONDS_WAITED=0
while [ "$(count buildrequests)" -le "${REQUESTS0}" ]; do
	if [ "${SECONDS_WAITED}" -ge 60 ]; then
		echo "FAIL: try did not create a build request"
		exit 1
	fi
	sleep 5
	SECONDS_WAITED=$(( SECONDS_WAITED + 5 ))
done

BRID="$(curl -s \
		"${BUILDBOTURL}/api/v2/buildrequests?order=-buildrequestid&limit=1" \
		| python3 -c \
		"import json, sys
print(json.load(sys.stdin)['buildrequests'][0]['buildrequestid'])")"

wait_build "${BRID}" "${COMMIT_SRC}"

SCHEDULER="$(curl -s \
		"${BUILDBOTURL}/api/v2/builds/${BUILDID}/properties" \
		| python3 -c \
		"import json, sys
properties = json.load(sys.stdin)['properties'][0]
print(properties.get('scheduler', ['?'])[0])")"
if [ "${SCHEDULER}" != "try" ]; then
	echo "FAIL: build ${BUILDID} was scheduled by ${SCHEDULER}"
	exit 1
fi
echo "PASS: build ${BUILDID} came from the try scheduler"

if step_log "${BUILDID}" "Clone postgres" \
		| grep -q "created by the buildbot try test"; then
	echo "PASS: the source step applied the patch"
else
	echo "FAIL: no patch in the Clone postgres step"
	exit 1
fi

RESULT="$(step_result "${BUILDID}" "Build database")"
if [ "${RESULT}" != "0" ]; then
	echo "FAIL: \"Build database\" finished with ${RESULT:-missing}," \
			"expected the non-force parameter path"
	exit 1
fi
echo "PASS: parameters came from the worker configuration"
