FROM python:3.12-slim-bookworm

# git is needed by the buildbot git poller.
RUN apt-get update \
        && apt-get install -y --no-install-recommends git \
        && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home buildbot

# Bake a clone of postgres.git pinned to a baseline commit for
# exercising the git poller.  Tests advance refs/heads/master through
# commits that are already in the pack, so no network access is needed
# at test time.  See docker/test-poller.sh.
ARG POSTGRES_REPO=https://github.com/postgres/postgres.git
ARG POLL_BASELINE=85df8c5bc7fe271bd17ffa1b84b972fabf964d40
RUN git clone --bare --single-branch --branch master --no-tags \
                "${POSTGRES_REPO}" /poll-repo \
        && git -C /poll-repo update-ref refs/heads/master \
                "${POLL_BASELINE}" \
        && chown -R buildbot:buildbot /poll-repo

WORKDIR /home/buildbot/master

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY buildbot.tac master.cfg general.py postgres.py dbt2.py dbt3.py \
     dbt5.py dbt7.py ./
COPY docker/master/settings.py ./
COPY docker/master/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chown -R buildbot:buildbot /home/buildbot/master

USER buildbot

EXPOSE 8010 8031 9989

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
