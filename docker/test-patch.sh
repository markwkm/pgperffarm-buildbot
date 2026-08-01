#!/bin/sh
# Force a dbt2 build on worker1 with an uploaded PostgreSQL patch, a
# DBT kit patch, and custom PostgreSQL configuration overrides, then
# verify the patches were applied and that the configuration reached
# the running server.  Run from the top of this repository while the
# compose environment is up.
set -e

# shellcheck source=docker/testlib.sh
. ./docker/testlib.sh

cat > "${TESTTMP}/postgresql.patch" <<'EOF'
--- /dev/null
+++ b/PGPERFFARM_PATCH_TEST.txt
@@ -0,0 +1 @@
+postgresql patch applied by the docker test environment
EOF

cat > "${TESTTMP}/dbt.patch" <<'EOF'
--- /dev/null
+++ b/PGPERFFARM_PATCH_TEST.txt
@@ -0,0 +1 @@
+dbt kit patch applied by the docker test environment
EOF

python3 - "${TESTTMP}" <<'PYEOF'
import base64
import json
import sys

tmp = sys.argv[1]

def b64(name):
    with open(f"{tmp}/{name}", 'rb') as f:
        return base64.b64encode(f.read()).decode()

params = {
    "reason": "patch submission test",
    "branch": "master",
    "warehouses": 1,
    "duration": 60,
    "connection_delay": 1,
    "connections_per_processor": 1,
    "parallelism": 4,
    "terminal_limit": 4,
    "postgresql.patch": b64('postgresql.patch'),
    "dbt.patch": b64('dbt.patch'),
    "custom_postgresql.conf":
        "# appended by the docker test environment\nwork_mem = 8MB\n",
}
with open(f"{tmp}/force.json", 'w') as f:
    json.dump({"jsonrpc": "2.0", "method": "force", "id": 1,
               "params": params}, f)
PYEOF

bb_login

echo "forcing a patched build on worker1"
BRID="$(curl -s -b "${COOKIES}" -H 'Content-Type: application/json' \
		--data @"${TESTTMP}/force.json" \
		"${BUILDBOTURL}/api/v2/forceschedulers/run-dbt2-worker1" \
		| python3 -c \
		"import json, sys
result = json.load(sys.stdin)['result']
print(list(result[1].values())[0])")"

wait_build "${BRID}"

for STEP in "Apply PostgreSQL patch" "Apply DBT kit patch" \
		"Add custom GUC overrides"; do
	RESULT="$(step_result "${BUILDID}" "${STEP}")"
	if [ "${RESULT}" != "0" ]; then
		echo "FAIL: step \"${STEP}\" finished with results" \
				"${RESULT:-missing}"
		exit 1
	fi
	echo "PASS: ${STEP}"
done

if step_log "${BUILDID}" "Capture PostgreSQL configuration" \
		| grep -q '^work_mem,8192,configuration file'; then
	echo "PASS: custom work_mem setting reached the server"
else
	echo "FAIL: work_mem override not found in pg_settings"
	exit 1
fi
