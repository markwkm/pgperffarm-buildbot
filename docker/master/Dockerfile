FROM python:3.12-slim-bookworm

# git is needed by the buildbot git poller.
RUN apt-get update \
        && apt-get install -y --no-install-recommends git \
        && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home buildbot

WORKDIR /home/buildbot/master

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY buildbot.tac master.cfg general.py postgres.py dbt2.py dbt3.py \
     dbt5.py dbt7.py ./
COPY docker/master/settings.py ./
COPY docker/master/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chown -R buildbot:buildbot /home/buildbot/master

USER buildbot

EXPOSE 8010 9989

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
