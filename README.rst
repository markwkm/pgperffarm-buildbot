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
build on each worker takes a while.  The git poller is disabled by
default so that starting the environment does not fetch all of
postgres.git; set *POLL_REPO* to enable polling a repository.  The
worker image's *WORKER_REF* build argument pins the pgperffarm-worker
revision being tested.
