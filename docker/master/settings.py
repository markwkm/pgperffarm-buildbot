"""
Buildbot master settings for the Docker Compose test environment,
driven by environment variables set in compose.yaml.
"""

import os

from buildbot.plugins import worker

workerNames = os.environ.get('WORKER_NAMES', 'worker1 worker2').split()
workerPassword = os.environ.get('WORKER_PASSWORD', 'secret')

# This is for logging into the Web site.
ADMINS = {
    os.environ.get('BUILDBOT_ADMIN', 'admin@example.com'):
        os.environ.get('BUILDBOT_ADMIN_PASSWORD', 'admin'),
    }

BUILDERS = {
    test: list(workerNames)
    for test in os.environ.get('TESTS', 'dbt2').split()
    }

BUILDBOT_URL = os.environ.get('BUILDBOT_URL', 'http://localhost:8010/')

DB_URL = "sqlite:///state.sqlite"

# Empty by default so bringing the stack up does not fetch all of
# postgres.git; use the force schedulers, or set POLL_REPO to poll.
POLL_REPO = os.environ.get('POLL_REPO', '')

WORKERS = [
    worker.Worker(name, workerPassword, max_builds=1)
    for name in workerNames
    ]

WWW_PORT = 8010
