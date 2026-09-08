#!/bin/bash
# A relative `filesystem_caches` path. The server resolves it under `<path>/caches`, so the
# entrypoint must leave it alone: preparing the value as written would make a directory beside the
# one the server actually opens.
set -eo pipefail

dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$dir/../lib.sh"

image="$1"

cid="$(
  docker run -d \
    -v "$dir/cache.xml":/etc/clickhouse-server/config.d/cache.xml:ro \
    --name "$(cname)" \
    "$image"
)"
trap 'docker rm -vf $cid > /dev/null' EXIT

chCli() {
  docker exec "$cid" clickhouse-client --query "$*"
}

# shellcheck source=../../../../../ci/tmp/docker-library/official-images/test/retry.sh
. "$TESTS_LIB_DIR/retry.sh" \
  --cid "$cid" \
  --image "$image" \
  --tries "$CLICKHOUSE_TEST_TRIES" \
  --sleep "$CLICKHOUSE_TEST_SLEEP" \
  chCli SELECT 1

data_dir="$(chCli "SELECT value FROM system.server_settings WHERE name = 'path'")"
[ "$(chCli "SELECT path FROM system.filesystem_cache_settings WHERE cache_name = 'docker_relative_cache'")" = "${data_dir}caches/docker_relative_cache" ]

# What pins the filter: the value as written must not have been prepared next to it.
! docker exec "$cid" test -e "${data_dir}docker_relative_cache"
