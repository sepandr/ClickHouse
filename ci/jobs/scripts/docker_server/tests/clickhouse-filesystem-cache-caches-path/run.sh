#!/bin/bash
# A relative per-cache `path` with `filesystem_caches_path` also set. The entrypoint prepares
# neither, and must not: the server resolves the entry under `<path>/caches` regardless of that
# setting, because `loadDefaultCaches` runs before `setFilesystemCachesPath` leaves it non-empty.
# Preparing the value under `filesystem_caches_path` would make a directory nothing ever opens, and
# would do it on a mount the entrypoint has no reason to touch.
set -eo pipefail

dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$dir/../lib.sh"

image="$1"

cid="$(
  docker run -d \
    -v /mnt/clickhouse-cache \
    -v "$dir/cache.xml":/etc/clickhouse-server/config.d/cache.xml:ro \
    --cap-drop=DAC_OVERRIDE \
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

# What the server actually resolved, which pins the ordering: if `filesystem_caches_path` ever did
# reach these entries, this is the assertion that would fail and send someone back to the filter.
[ "$(chCli "SELECT path FROM system.filesystem_cache_settings WHERE cache_name = 'docker_caches_path_cache'")" = "${data_dir}caches/docker_caches_path_cache" ]

# The mount named by `filesystem_caches_path` is left alone.
[ -z "$(docker exec "$cid" sh -c 'ls -A /mnt/clickhouse-cache')" ]

# And the value as written was not prepared under the data directory either, which is where it
# would land if the entrypoint stopped filtering relative entries.
! docker exec "$cid" test -e "${data_dir}docker_caches_path_cache"
