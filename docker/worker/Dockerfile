FROM debian:bookworm-slim

# Toolchain and libraries for building PostgreSQL and the DBT kits,
# sysstat for the test statistics, and a locale for initdb.
RUN apt-get update \
        && apt-get install -y --no-install-recommends \
                bc \
                bison \
                ca-certificates \
                cmake \
                flex \
                g++ \
                gcc \
                git \
                libev-dev \
                libpq-dev \
                libreadline-dev \
                libsqlite3-dev \
                locales \
                make \
                patch \
                perl \
                pkg-config \
                procps \
                python3 \
                python3-venv \
                rsync \
                sqlite3 \
                sysstat \
                zlib1g-dev \
        && rm -rf /var/lib/apt/lists/* \
        && sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
        && locale-gen

ENV LANG=en_US.UTF-8

RUN python3 -m venv /opt/buildbot \
        && /opt/buildbot/bin/pip install --no-cache-dir buildbot-worker
ENV PATH="/opt/buildbot/bin:${PATH}"

# The touchstone tools provide the ts command the DBT kits use to
# collect system and database statistics during a test.
ARG TOUCHSTONE_REF=main
RUN git clone https://gitlab.com/touchstone/touchstone-tools.git \
                /tmp/touchstone-tools \
        && git -C /tmp/touchstone-tools checkout "${TOUCHSTONE_REF}" \
        && cmake -S /tmp/touchstone-tools -B /tmp/touchstone-tools/build \
        && cmake --build /tmp/touchstone-tools/build \
        && cmake --install /tmp/touchstone-tools/build \
        && rm -rf /tmp/touchstone-tools

RUN useradd --create-home buildbot

# The worker directory comes from the pgperffarm-worker repository,
# pinned by WORKER_REF.
ARG WORKER_REPO=https://github.com/PGPerfFarm/pgperffarm-worker.git
ARG WORKER_REF=main

RUN git clone "${WORKER_REPO}" /home/buildbot/worker \
        && git -C /home/buildbot/worker checkout "${WORKER_REF}"

COPY test/ /home/buildbot/worker/test/
COPY guc/ /home/buildbot/worker/guc/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chown -R buildbot:buildbot /home/buildbot/worker

USER buildbot
WORKDIR /home/buildbot/worker

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
