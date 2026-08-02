#!/bin/sh
# Exercise the git poller against the pinned repository baked into the
# master image at /poll-repo.  A commit that does not touch src/ must
# not trigger a build, and a commit that does touch src/ must.  Run
# from the top of this repository while the compose environment is up.
set -e

# Seconds to wait for the poller to notice a ref move.
POLLWAIT="${POLLWAIT:-120}"

# shellcheck source=docker/testlib.sh
. ./docker/testlib.sh
# shellcheck source=docker/fixture.sh
. ./docker/fixture.sh

wait_api

advance()
{
	docker compose exec -T master \
			git -C /poll-repo update-ref refs/heads/master "${1}"
}

wait_for_changes()
{
	SECONDS_WAITED=0
	while [ "${SECONDS_WAITED}" -lt "${POLLWAIT}" ]; do
		if [ "$(count changes)" -ge "${1}" ]; then
			return 0
		fi
		sleep 5
		SECONDS_WAITED=$(( SECONDS_WAITED + 5 ))
	done
	echo "FAIL: timed out waiting for change ${1} to be recorded"
	exit 1
}

echo "resetting master to the baseline ${BASELINE}"
advance "${BASELINE}"
# The rewind emits no change; give the poller one cycle to record the
# new head so that the following moves are diffed against it.
sleep 45

CHANGES0="$(count changes)"
REQUESTS0="$(count buildrequests)"

echo "advancing master to doc-only commit ${COMMIT_DOC}"
advance "${COMMIT_DOC}"
wait_for_changes $(( CHANGES0 + 1 ))
# Give the scheduler a moment to react, wrongly, to the change.
sleep 15
REQUESTS1="$(count buildrequests)"
if [ "${REQUESTS1}" -ne "${REQUESTS0}" ]; then
	echo "FAIL: the doc-only commit created a build request"
	exit 1
fi
echo "PASS: the doc-only commit did not trigger a build"

echo "advancing master to src/ commit ${COMMIT_SRC}"
advance "${COMMIT_SRC}"
wait_for_changes $(( CHANGES0 + 2 ))
SECONDS_WAITED=0
while [ "${SECONDS_WAITED}" -lt 30 ]; do
	if [ "$(count buildrequests)" -gt "${REQUESTS0}" ]; then
		echo "PASS: the src/ commit triggered a build"
		exit 0
	fi
	sleep 5
	SECONDS_WAITED=$(( SECONDS_WAITED + 5 ))
done
echo "FAIL: the src/ commit did not trigger a build"
exit 1
