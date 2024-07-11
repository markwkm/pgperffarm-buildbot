#!/usr/bin/env python

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

    if branch == "master":
        command = ['git', 'log', 'master', '--pretty=format:"%H"', '--', 'src']
    else:
        command = ['git', 'log', branch, '^master', '--pretty=format:"%H"',
                   '--', 'src']

    count = 1
    with subprocess.Popen(command, stdout=subprocess.PIPE, text=True) as pipe:
        for line in pipe.stdout:
            commit = line.strip().strip('"')
            if args.verbose:
                print(f"{count}: queueing commit {commit}")

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
                    if args.dry_run:
                        break
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
                    if args.dry_run:
                        break
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
                    if args.dry_run:
                        break
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
                    if args.dry_run:
                        break
                    r = s.post(
                            f"{args.buildbot}/api/v2/forceschedulers/run-dbt7-{worker}" ,
                            data=json.dumps(data), headers=headers)

            count = count + 1
            if args.limit != 0 and count > args.limit:
                sys.exit(0)
