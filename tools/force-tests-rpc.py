#!/usr/bin/env python3
"""Script to queue batches of tests."""

import subprocess
import argparse
import getpass
import json
import requests


PARAMETERS = {
    "dbt2": {
        "reason": "force jsonrpc",
        "warehouses": 1,
        "duration": 120,
        "connection_delay": 1,
        "connections_per_processor": 1,
        "terminal_limit": 1,
        "parallelism": 1,
    },
    "dbt3": {
        "reason": "force jsonrpc",
        "scale": 1,
        "duration": 120,
        "connection_delay": 1,
        "connections_per_processor": 1,
        "terminal_limit": 1,
        "parallelism": 1,
    },
    "dbt5": {
        "reason": "force jsonrpc",
        "customers": 1000,
        "duration": 120,
        "connection_delay": 1,
        "users": 1,
        "parallelism": 1,
    },
    "dbt7": {
        "reason": "force jsonrpc",
        "scale": 1,
        "duration": 120,
        "connection_delay": 1,
        "connections_per_processor": 1,
        "terminal_limit": 1,
        "parallelism": 1,
    },
}

def find_test_for_commit(test0, name, revision):
    """Check if a test has run for a given commit."""
    query = f"""
        SELECT 1
          FROM builds
               JOIN build_properties AS revision
                 ON revision.buildid = builds.id
                AND revision.name = 'revision'
               JOIN build_properties AS got_revision
                 ON got_revision.buildid = builds.id
                AND got_revision.name = 'got_revision'
               JOIN builders
                 ON builderid = builders.id
               JOIN workers
                 ON workerid = workers.id
                AND workers.name = '{name}'
          WHERE builds.results = 0
            AND (
                    builders.name = '{test0}'
                 OR builders.name LIKE '{test0}-%'
                )
            AND (
                    revision.value = '"{revision}"'
                 OR got_revision.value = '"{revision}"'
                )
    """
    result = subprocess.run(
        ['psql', '-XAt', '-d', 'perffarm', '-c', query],
        stdout=subprocess.PIPE,
        text=True,
        check=False,
    )
    return result.stdout.strip() == '1'


parser = argparse.ArgumentParser(
        description="""
        Queue up performance tests to run.  Must run this script from withing a
        PostgreSQL git repository:
        git clone --bare https://github.com/postgres/postgres.git
        """
        )

parser.add_argument(
        '--branch',
        action='append',
        required=True,
        help='PostgreSQL branch to queue up tests against',
        )
parser.add_argument(
        '--buildbot',
        default='http://147.75.56.225:8010',
        help='Buildbot URL',
        )
parser.add_argument(
        '--dry-run',
        action='store_true',
        default=False,
        help='do not actually submit a build request',
        )
parser.add_argument(
        '--limit',
        type=int,
        default=20,
        help='limit the number of commits to queue for testing',
        )
parser.add_argument(
        '--only-missing',
        action='store_true',
        default=False,
        help='queue test only if commit has not been tested yet',
        )
parser.add_argument(
        '--revision',
        help='git commit revision to start at',
        )
parser.add_argument(
        '--test',
        action='append',
        default=None,
        help='test to run (dbt2, dbt3, dbt5, dbt7)',
        )
parser.add_argument(
        '--user',
        required=True,
        help='Buildbot login',
        )
parser.add_argument(
        '--verbose',
        action='store_true',
        default=False,
        help='verbose output',
        )
parser.add_argument(
        '--worker',
        action='append',
        default=[],
        help='workers to queue tests on (default: all)',
        )

args = parser.parse_args()

if not args.dry_run:
    secret = getpass.getpass('secret: ')

if args.test is None:
    args.test = ["dbt2", "dbt3", "dbt5", "dbt7"]

headers = {'Content-Type': 'application/json'}
data = {
        "jsonrpc": "2.0",
        "method": "force",
        "id": 5432,
        }

s = requests.Session()
if not args.dry_run:
    r = s.get(f"{args.buildbot}/auth/login", auth=(args.user, secret))

if not args.worker:
    r = requests.get(f"{args.buildbot}/api/v2/workers", timeout=60)
    args.worker = worker_names = [worker['name'] for worker in r.json().get('workers', [])]

if args.verbose:
    print(f"Branches: {args.branch}")
    print(f"Limit: {args.limit}")
    print(f"Tests: {args.test}")
    print(f"Workers: {args.worker}")

for branch in args.branch:
    if args.verbose:
        print(f"queueing for branch {branch}")

    command = ['git', 'checkout', branch]
    subprocess.run(command, stdout=subprocess.PIPE, text=True, check=False)
    command = ['git', 'pull']
    subprocess.run(command, stdout=subprocess.PIPE, text=True, check=False)

    command = ['git', 'log']
    if args.limit:
        command.append(f'-{args.limit}')
    command.append('--pretty=format:"%H"')
    if args.revision:
        command.append(args.revision)
    command.extend(['--', 'src'])

    with subprocess.Popen(command, stdout=subprocess.PIPE, text=True) as pipe:
        count = 1
        for line in pipe.stdout:
            commit = line.strip().strip('"')

            if args.verbose:
                pcmd = ['git', 'log', '-1', '--pretty=format:"%s - %aD"',
                        '--date=format:"%Y-%m-%d"', commit]
                r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True,
                                   check=False)
                message = r.stdout.strip().strip('"')

                print(f'{count}: commit {commit} {message}')

            for test in args.test:
                data['params'] = PARAMETERS[test].copy()
                data['params']['revision'] = commit
                data['params']['branch'] = branch
                data['params']['owner'] = args.user

                for worker in args.worker:
                    if args.only_missing:
                        found = find_test_for_commit(test, worker, commit)
                        if found:
                            if args.verbose:
                                print(f'  {test}: {worker} exists')
                        else:
                            if args.verbose:
                                print(f'  {test}: {worker} missed')
                    else:
                        found = False
                        if args.verbose:
                            print(f'  {test}: {worker} queue')

                    if not args.dry_run and not found:
                        r = s.post(
                                f"{args.buildbot}/api/v2/forceschedulers/run-{test}-{worker}" ,
                                data=json.dumps(data), headers=headers)
                        if r.status_code < 200 or r.status_code >= 300:
                            print(r.text)

            count = count + 1
            if args.limit != 0 and count > args.limit:
                break
