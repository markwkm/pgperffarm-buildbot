#!/usr/bin/env python3

import sys
import subprocess
import argparse
import getpass
import json
import requests

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
        default=[],
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

secret = getpass.getpass('secret: ')

headers = {'Content-Type': 'application/json'}
data = {
        "jsonrpc": "2.0",
        "method": "force",
        "id": 5432,
        }

s = requests.Session()
r = s.get(f"{args.buildbot}/auth/login", auth=(args.user, secret))

if not args.worker:
    r = requests.get(f"{args.buildbot}/api/v2/workers")
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
    subprocess.run(command, stdout=subprocess.PIPE, text=True)
    command = ['git', 'pull']
    subprocess.run(command, stdout=subprocess.PIPE, text=True)

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
                r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True)
                message = r.stdout.strip().strip('"')

                print(f'{count}: commit {commit} {message}')

            # dbt2
            if not args.test or 'dbt2' in args.test:
                data['params'] = {
                        "reason": "force jsonrpc",
                        "revision": commit,
                        "branch": branch,
                        "owner": args.user,
                        "warehouses": 1,
                        "duration": 120,
                        "connection_delay": 1,
                        "connections_per_processor": 1,
                        "terminal_limit": 1
                        }

                for worker in args.worker:
                    if args.only_missing:
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
                                        AND workers.name = '{worker}'
                                  WHERE builds.results = 0
                                    AND (
                                            builders.name = 'dbt2'
                                         OR builders.name LIKE 'dbt2-%'
                                        )
                                    AND (
                                            revision.value = '"{commit}"'
                                         OR got_revision.value = '"{commit}"'
                                        )
                                """
                        pcmd = ['psql', '-XAt', '-d', 'perffarm', '-c', query]
                        r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True)
                        found = r.stdout.strip()

                        if found == '1':
                            if args.verbose:
                                print(f'  dbt2: {worker} exists')
                        else:
                            found = '0'
                            if args.verbose:
                                print(f'  dbt2: {worker} missed')
                    else:
                        found = '0'
                        if args.verbose:
                            print(f'  dbt2: {worker} queue')

                    if not args.dry_run and found == '0':
                        r = s.post(
                                f"{args.buildbot}/api/v2/forceschedulers/run-dbt2-{worker}" ,
                                data=json.dumps(data), headers=headers)

            # dbt3
            if not args.test or 'dbt3' in args.test:
                data['params'] = {
                        "reason": "force jsonrpc",
                        "revision": commit,
                        "branch": branch,
                        "owner": args.user,
                        "scale": 1,
                        "duration": 120,
                        "connection_delay": 1,
                        "connections_per_processor": 1,
                        "terminal_limit": 1
                        }

                for worker in args.worker:
                    if args.only_missing:
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
                                        AND workers.name = '{worker}'
                                  WHERE builds.results = 0
                                    AND (
                                            builders.name = 'dbt3'
                                         OR builders.name LIKE 'dbt3-%'
                                        )
                                    AND (
                                            revision.value = '"{commit}"'
                                         OR got_revision.value = '"{commit}"'
                                        )
                                """
                        pcmd = ['psql', '-XAt', '-d', 'perffarm', '-c', query]
                        r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True)
                        found = r.stdout.strip()

                        if found == '1':
                            if args.verbose:
                                print(f'  dbt3: {worker} exists')
                        else:
                            found = '0'
                            if args.verbose:
                                print(f'  dbt3: {worker} missed')
                    else:
                        found = '0'
                        if args.verbose:
                            print(f'  dbt3: {worker} queue')

                    if not args.dry_run and found == '0':
                        r = s.post(
                                f"{args.buildbot}/api/v2/forceschedulers/run-dbt3-{worker}" ,
                                data=json.dumps(data), headers=headers)

            # dbt5
            if not args.test or 'dbt5' in args.test:
                data['params'] = {
                        "reason": "force jsonrpc",
                        "revision": commit,
                        "branch": branch,
                        "owner": args.user,
                        "customers": 1000,
                        "duration": 120,
                        "connection_delay": 1,
                        "users": 1,
                        }

                for worker in args.worker:
                    if args.only_missing:
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
                                        AND workers.name = '{worker}'
                                  WHERE builds.results = 0
                                    AND (
                                            builders.name = 'dbt5'
                                         OR builders.name LIKE 'dbt5-%'
                                        )
                                    AND (
                                            revision.value = '"{commit}"'
                                         OR got_revision.value = '"{commit}"'
                                        )
                                """
                        pcmd = ['psql', '-XAt', '-d', 'perffarm', '-c', query]
                        r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True)
                        found = r.stdout.strip()

                        if found == '1':
                            if args.verbose:
                                print(f'  dbt5: {worker} exists')
                        else:
                            found = '0'
                            if args.verbose:
                                print(f'  dbt5: {worker} missed')
                    else:
                        found = '0'
                        if args.verbose:
                            print(f'  dbt5: {worker} queue')

                    if not args.dry_run and found == '0':
                        r = s.post(
                                f"{args.buildbot}/api/v2/forceschedulers/run-dbt5-{worker}" ,
                                data=json.dumps(data), headers=headers)

            # dbt7
            if not args.test or 'dbt7' in args.test:
                data['params'] = {
                        "reason": "force jsonrpc",
                        "revision": commit,
                        "branch": branch,
                        "owner": args.user,
                        "scale": 1,
                        "duration": 120,
                        "connection_delay": 1,
                        "connections_per_processor": 1,
                        "terminal_limit": 1
                        }

                for worker in args.worker:
                    if args.only_missing:
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
                                        AND workers.name = '{worker}'
                                  WHERE builds.results = 0
                                    AND (
                                            builders.name = 'dbt7'
                                         OR builders.name LIKE 'dbt7-%'
                                        )
                                    AND (
                                            revision.value = '"{commit}"'
                                         OR got_revision.value = '"{commit}"'
                                        )
                                """
                        pcmd = ['psql', '-XAt', '-d', 'perffarm', '-c', query]
                        r = subprocess.run(pcmd, stdout=subprocess.PIPE, text=True)
                        found = r.stdout.strip()

                        if found == '1':
                            if args.verbose:
                                print(f'  dbt7: {worker} exists')
                        else:
                            found = '0'
                            if args.verbose:
                                print(f'  dbt7: {worker} missed')
                    else:
                        found = '0'
                        if args.verbose:
                            print(f'  dbt7: {worker} queue')

                    if not args.dry_run and found == '0':
                        r = s.post(
                                f"{args.buildbot}/api/v2/forceschedulers/run-dbt7-{worker}" ,
                                data=json.dumps(data), headers=headers)

            count = count + 1
            if args.limit != 0 and count > args.limit:
                break
