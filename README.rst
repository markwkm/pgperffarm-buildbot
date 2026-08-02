PostgreSQL(R) Performance Farm Buildbot
=======================================

The PostgreSQL(R) Performance Farm Buildbot project's goal is for managing the
execution of performance tests.

The goals of this project include:

1. Automatically initiate tests on changes only to PostgreSQL(R) code changes
2. Queue up tests on previous code changes
3. Re-run tests
4. Submit patches directly to Buildbot for testing
5. Allow Buildbot worker specific test parameters

--------------------------------------
Initiating tests from the command line
--------------------------------------

The force schedulers can be driven over the JSON-RPC API with
``tools/force-tests-rpc.py``.  It walks a PostgreSQL git repository
and queues a build for each commit that touches ``src/``, so tests can
be queued against a series of commits, one branch at a time.  Run it
from inside a clone of postgres.git::

    git clone --bare https://github.com/postgres/postgres.git
    cd postgres.git
    /path/to/pgperffarm-buildbot/tools/force-tests-rpc.py \
        --buildbot http://localhost:8010 \
        --user admin@example.com \
        --branch master \
        --limit 1 \
        --test dbt2 \
        --worker worker1

The script prompts for the Buildbot login secret before queueing.
Repeat ``--branch``, ``--test``, and ``--worker`` to cover more
combinations; omitting ``--worker`` queues tests on every registered
worker.  Use ``--dry-run`` to preview what would be queued, and
``--only-missing`` to skip commits that already have a successful
result recorded in the perffarm database (requires ``psql`` access to
it).

--------------------------
Submitting a patch to test
--------------------------

Each test's force dialog accepts three optional file uploads:
PostgreSQL configuration overrides, a patch to apply to PostgreSQL,
and a patch to apply to the DBT kit.  The patches must be base64
encoded::

    base64 fix.patch > fix.patch.b64

In the web interface, open the builder for the wanted test and worker
combination (e.g. ``dbt2-worker1``), press the force button, and
upload the encoded patch in the appropriate field.

When the master enables it with *TRY_USERS* (see
``settings.py.sample``), a PostgreSQL patch can also be submitted
with Buildbot's own try command, which applies the plain, unencoded
diff to the requested revision during checkout::

    buildbot try --connect=pb --master=<master>:8031 \
        --username=developer --passwd=password \
        --who=developer \
        --repository=https://github.com/postgres/postgres.git \
        --branch=master --baserev=<commit> \
        --diff=fix.patch --patchlevel=1 \
        --builder=dbt2-worker1

A try build reads its test parameters from the worker's test
configuration files, like a polled build, and the patch applies only
to PostgreSQL, not to the DBT kit.

The force parameters can also be supplied through the JSON-RPC API.
Log in first to get a session cookie, then POST a force request with
the patch inline (``tr`` strips the newlines that JSON strings cannot
carry)::

    curl -s -c cookies.txt -u admin@example.com \
        http://localhost:8010/auth/login
    curl -s -b cookies.txt -H 'Content-Type: application/json' \
        --data @- \
        http://localhost:8010/api/v2/forceschedulers/run-dbt2-worker1 \
        <<EOF
    {"jsonrpc": "2.0", "method": "force", "id": 1, "params": {
        "reason": "testing fix.patch",
        "warehouses": 1,
        "duration": 120,
        "connection_delay": 1,
        "connections_per_processor": 1,
        "parallelism": 20,
        "terminal_limit": 1000,
        "postgresql.patch": "$(base64 fix.patch | tr -d '\n')"}}
    EOF

---------------------------
Testing with Docker Compose
---------------------------

A Docker Compose environment is provided for functional testing of the
whole system: a Buildbot master built from this repository and two
workers built from the `pgperffarm-worker
<https://github.com/PGPerfFarm/pgperffarm-worker>`_ repository.  It is
meant for exercising the configuration, not for producing meaningful
performance results.

Build and start everything::

    docker compose up --build

The web interface is served at http://localhost:8010/ and the force
schedulers can be used after logging in as *admin@example.com* with
password *admin*.  See ``compose.yaml`` for all of the defaults.

Each build clones and compiles PostgreSQL from source, so the first
build on each worker takes a while.  The worker image's *WORKER_REF*
build argument pins the pgperffarm-worker revision being tested.

Testing the git poller
~~~~~~~~~~~~~~~~~~~~~~

The master image bakes a clone of postgres.git into ``/poll-repo``
with ``refs/heads/master`` pinned to the *POLL_BASELINE* build
argument, and the master polls it (see *POLL_REPO* and
*POLL_INTERVAL* in ``compose.yaml``).  Because the clone contains
history past the baseline, tests can advance the branch through real
commits with ``git update-ref`` and no network access::

    sh docker/test-poller.sh

The script advances master to a commit that does not touch ``src/``
and verifies that no build is triggered, then to a commit that does
and verifies that one is.  Since the commits are real postgres.git
commits, the triggered build can run to completion.  Note the poller
copies the repository into its own working directory on the first
poll after the master container is created.

Testing forced revisions
~~~~~~~~~~~~~~~~~~~~~~~~

To verify that forced builds test the requested commit, run::

    sh docker/test-force.sh

The script forces dbt2 builds of two specific revisions, the pinned
baseline on worker1 and the poller test's ``src/`` commit on worker2,
waits for both builds to finish, and checks that each build's
got_revision property records the requested revision.  The two
builds compile PostgreSQL in parallel, so expect the script to run
for as long as the slower build.

Testing patch submission
~~~~~~~~~~~~~~~~~~~~~~~~

To verify the force upload parameters, run::

    sh docker/test-patch.sh

The script forces a dbt2 build on worker1 that carries a PostgreSQL
patch, a DBT kit patch, and a ``work_mem`` override, then verifies
that both patches applied and that the override shows up in the
captured ``pg_settings`` output.

Testing buildbot try
~~~~~~~~~~~~~~~~~~~~

To verify patch submission with Buildbot's try command, run::

    sh docker/test-try.sh

The script submits a patch that creates a file under ``src/``
against a pinned PostgreSQL revision, running the try client inside
the master container, and verifies that the requested revision was
checked out, that the source step applied the patch, and that the
build read its parameters from the worker's test configuration.

Running the whole suite
~~~~~~~~~~~~~~~~~~~~~~~

To go from nothing to a fully validated environment with one
command, run::

    sh docker/test-all.sh

It builds the images, starts the environment, waits for the workers
to connect, runs all of the test scripts, and waits for every
triggered build to finish.  Expect several PostgreSQL builds' worth
of run time.
