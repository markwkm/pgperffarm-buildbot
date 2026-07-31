"""
These are common steps specific for PostgreSQL.
"""

from buildbot.plugins import steps, util

import general

PGINITDB = [
        steps.ShellCommand(
            name="Initialize postgres instance",
            command=[
                'initdb',
                '-D', util.Interpolate("%(prop:builddir)s/pgdata"),
                '-A', 'trust',
                '-E', 'UTF-8',
                '--locale=en_US.UTF-8',
                ],
            env={'PATH': util.Interpolate(
                "%(prop:builddir)s/usr/bin:${PATH}")},
            haltOnFailure=True,
            ),
        steps.ShellCommand(
            name="Copy test specific GUCs",
            command=[
                '/bin/sh', '-c',
                util.Interpolate(
                        "cat %(prop:builddir)s/../guc/"
                        "$(echo %(prop:buildername)s | cut -d '-' -f 1)"
                        ".%(prop:branch:~master)s.conf"
                        " >> %(prop:builddir)s/pgdata/postgresql.auto.conf"
                        ),
                ],
            haltOnFailure=True,
            ),
        steps.StringDownload(
            util.Interpolate("%(prop:custom_postgresql.conf)s"),
            name="Transfer custom GUC overrides",
            doStepIf=general.hasproperty("custom_postgresql.conf"),
            haltOnFailure=True,
            workerdest="../custom_postgresql.conf",
            ),
        steps.ShellCommand(
            name="Add custom GUC overrides",
            doStepIf=general.hasproperty("custom_postgresql.conf"),
            command=[
                '/bin/sh', '-c',
                util.Interpolate(
                        "cat %(prop:builddir)s/custom_postgresql.conf"
                        " >> %(prop:builddir)s/pgdata/postgresql.auto.conf"
                        ),
                ],
            haltOnFailure=True,
            ),
        ]

PGINSTALL = [
        steps.Git(
            name="Clone postgres",
            repourl='https://github.com/postgres/postgres.git',
            branch='master',
            mode='full',
            method='fresh',
            haltOnFailure=True,
            ),
        steps.StringDownload(
            util.Interpolate("%(prop:postgresql.patch)s"),
            name="Transfer PostgreSQL patch",
            doStepIf=general.hasproperty("postgresql.patch"),
            haltOnFailure=True,
            workerdest="../postgresql.patch",
            ),
        steps.ShellCommand(
            name="Apply PostgreSQL patch",
            doStepIf=general.hasproperty("postgresql.patch"),
            command=[
                '/bin/sh', '-c',
                'base64 -d ../postgresql.patch | patch -p1',
                ],
            haltOnFailure=True,
            ),
        steps.Configure(
            name="Configure postgres",
            command=[
                './configure',
                util.Interpolate("--prefix=%(prop:builddir)s/usr"),
                '--without-icu'],
            haltOnFailure=True,
            ),
        steps.Compile(
            name="Build postgres",
            command=['/bin/sh', '-c', 'make -j $(nproc)'],
            haltOnFailure=True,
            ),
        steps.Compile(
            name="Install postgres",
            command=['make', 'install'],
            haltOnFailure=True,
            ),
    ]

PGSTART = [
        steps.ShellCommand(
            name="Start postgres",
            command=[
                'pg_ctl',
                '-D', util.Interpolate("%(prop:builddir)s/pgdata"),
                'start',
                '-l', util.Interpolate("%(prop:builddir)s/pgdata/pg.log"),
                ],
            env={'PATH': util.Interpolate(
                "%(prop:builddir)s/usr/bin:${PATH}")},
            haltOnFailure=True,
            ),
        steps.ShellCommand(
            name="Capture PostgreSQL configuration",
            command=[
                'psql', '-c',
                'COPY (SELECT name, setting, source FROM pg_settings ' \
                        'ORDER BY lower(name)) TO STDOUT (FORMAT CSV, HEADER)',
                ],
            env={
                'PATH': util.Interpolate("%(prop:builddir)s/usr/bin:${PATH}"),
                'PGDATABASE': 'postgres',
                 },
            haltOnFailure=True,
            ),
        ]

PGSTOP = [
        steps.ShellCommand(
            name="Stop postgres",
            command=[
                'pg_ctl',
                '-D', util.Interpolate("%(prop:builddir)s/pgdata"),
                'stop',
                '-m', 'immediate',
                ],
            env={'PATH': util.Interpolate(
                "%(prop:builddir)s/usr/bin:${PATH}")
                },
            alwaysRun=True,
            ),
        ]
