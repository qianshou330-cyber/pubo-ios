#!/usr/bin/env bash
# Called only after the Ubuntu workflow has created its disposable network namespace
# and dropped root privileges. Outside acquisition is not part of this launcher.
set -euo pipefail
[[ $# -ge 3 && "$(id -u)" != 0 ]]
repo=$1
scratch=$2
evidence=$3
actual_namespace=$(readlink /proc/self/ns/net)
[[ $actual_namespace != "$WORLD_HOST_NETNS" ]]
links=$(ip -o link show)
route_v4=$(ip -o route show table main)
route_v6=$(ip -o -6 route show table main)
[[ "$links" =~ ^[0-9]+:\ lo:\  && "$links" != *$'\n'* && -z "$route_v4" && -z "$route_v6" ]]
printf 'host=%s\nreplay=%s\nlinks=%s\nIPv4 and IPv6 main route tables empty\n' \
  "$WORLD_HOST_NETNS" "$actual_namespace" "$links" > "$evidence/network-isolation.txt"
export WORLD_VERIFIED_SOURCE="$repo"
if [[ $# == 3 || ${4-} == fresh-smoke ]]; then
  WORLD_CHROMIUM_SMOKE=1 node --test "$repo/scripts/h5-capture/test-world-replay.mjs" \
    2>&1 | tee "$evidence/chromium-smoke.log"
fi
case "${4-historical}" in
  historical)
    [[ $# == 3 ]]
    node "$repo/scripts/h5-capture/capture-world-pinned.mjs" \
      "$repo" "$scratch/static" "$evidence/replay" 2>&1 | tee "$evidence/replay.log";;
  fresh-smoke) [[ $# == 4 ]];;
  fresh-probe)
    [[ $# == 6 && $6 =~ ^[0-8]$ ]]
    node "$repo/scripts/h5-capture/capture-world-pinned.mjs" \
      "$repo" "$scratch/fresh" "$evidence/probe-$6" fresh-probe "$5" "$6" \
      2>&1 | tee "$evidence/probe-$6.log";;
  fresh-final)
    [[ $# == 5 ]]
    node "$repo/scripts/h5-capture/capture-world-pinned.mjs" \
      "$repo" "$scratch/fresh" "$evidence/replay" fresh-final "$5" \
      2>&1 | tee "$evidence/replay.log";;
  *) exit 2;;
esac
