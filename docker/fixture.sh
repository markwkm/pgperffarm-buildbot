# Fixture commits shared by the docker test scripts.
# shellcheck disable=SC2034  # used by the sourcing scripts

# The pinned baseline of /poll-repo in the master image; keep in sync
# with the POLL_BASELINE build argument in docker/master/Dockerfile.
BASELINE="85df8c5bc7fe271bd17ffa1b84b972fabf964d40"

# Consecutive commits on postgres.git master following the baseline:
# touches only doc/src/sgml/, and must not trigger a polled build.
COMMIT_DOC="78758d37306cd89ab060f00cb06f249018d5b8da"
# Touches src/backend/ and src/include/, and must trigger one.
COMMIT_SRC="e65c331b8fbf8c9632b62c5a9dcb589cbd3046a8"
