# Shared helpers for the docker test scripts.
# shellcheck disable=SC2034  # variables are used by sourcing scripts

BUILDBOTURL="${BUILDBOTURL:-http://localhost:8010}"
BUILDBOT_USER="${BUILDBOT_USER:-admin@example.com}"
BUILDBOT_PASSWORD="${BUILDBOT_PASSWORD:-admin}"
# Seconds to wait for a build to finish.
BUILDWAIT="${BUILDWAIT:-3600}"

TESTTMP="$(mktemp -d)"
trap 'rm -rf "${TESTTMP}"' EXIT
COOKIES="${TESTTMP}/cookies"

# Log in and store the session cookie in ${COOKIES}.
bb_login()
{
	curl -s -c "${COOKIES}" \
			-u "${BUILDBOT_USER}:${BUILDBOT_PASSWORD}" \
			"${BUILDBOTURL}/auth/login" > /dev/null
}

# Print the total number of records of an API collection.
count()
{
	curl -s "${BUILDBOTURL}/api/v2/${1}" | python3 -c \
	"import json, sys; print(json.load(sys.stdin)['meta']['total'])"
}

# Print the results code of the named step of a build.
step_result()
{
	curl -s "${BUILDBOTURL}/api/v2/builds/${1}/steps" | python3 -c "
import json, sys
for step in json.load(sys.stdin)['steps']:
    if step['name'] == '${2}':
        print(step['results'])
        break"
}

# Print all logs of the named step of a build.
step_log()
{
	python3 - "${BUILDBOTURL}" "${1}" "${2}" <<'PYEOF'
import json
import sys
import urllib.request

url, buildid, name = sys.argv[1:4]
with urllib.request.urlopen(f"{url}/api/v2/builds/{buildid}/steps") as f:
    steps = json.load(f)['steps']
step = next(s for s in steps if s['name'] == name)
with urllib.request.urlopen(
        f"{url}/api/v2/steps/{step['stepid']}/logs") as f:
    logs = json.load(f)['logs']
for log in logs:
    with urllib.request.urlopen(
            f"{url}/api/v2/logs/{log['logid']}/raw_inline") as f:
        sys.stdout.write(f.read().decode())
PYEOF
}

# Wait for the build claiming build request ${1} to finish
# successfully, leaving its id in ${BUILDID}.  If ${2} is given,
# verify the build's got_revision property records it.
wait_build()
{
	BRID="${1}"
	WANTED="${2:-}"

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

	if [ -n "${WANTED}" ]; then
		GOT="$(curl -s \
				"${BUILDBOTURL}/api/v2/builds/${BUILDID}/properties" \
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
	else
		echo "PASS: build ${BUILDID} finished successfully"
	fi
}

# Wait for every build request and build to complete, failing if any
# build failed.
wait_quiet()
{
	SECONDS_WAITED=0
	while [ "${SECONDS_WAITED}" -lt "${BUILDWAIT}" ]; do
		if [ "$(count 'buildrequests?complete=false')" -gt 0 ]; then
			STATE="building"
		else
			STATE="$(curl -s "${BUILDBOTURL}/api/v2/builds" \
					| python3 -c "
import json, sys
builds = json.load(sys.stdin)['builds']
if not all(b['complete'] for b in builds):
    print('building')
elif any(b['results'] > 1 for b in builds):
    print('failed')
else:
    print('done')")"
		fi
		case "${STATE}" in
		done)
			return 0
			;;
		failed)
			echo "FAIL: a build failed"
			exit 1
			;;
		esac
		sleep 30
		SECONDS_WAITED=$(( SECONDS_WAITED + 30 ))
	done
	echo "FAIL: builds did not finish in ${BUILDWAIT}s"
	exit 1
}
