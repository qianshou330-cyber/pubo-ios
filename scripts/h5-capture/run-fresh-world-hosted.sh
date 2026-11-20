#!/usr/bin/env bash
# Execute only on the optional Ubuntu job; acquisition and browser never share a process or network namespace.
set -euo pipefail
[[ $# == 3 && "$(id -u)" != 0 ]]
repo=$1 scratch=$2 evidence=$3
[[ "$(git -C "$repo" rev-parse HEAD)" == "$GITHUB_SHA" ]]
node_bin=$(realpath "$(command -v node)")
host_netns=$(readlink /proc/self/ns/net)
runner_user=$(id -un)
run_isolated() {
  sudo --non-interactive /usr/bin/unshare --net -- /bin/bash -euc '
    /usr/sbin/ip link set dev lo up
    run_user=$1 repo=$2 scratch=$3 evidence=$4 commit=$5 netns=$6 node=$7
    shift 7
    exec /usr/sbin/runuser -u "$run_user" -- /usr/bin/env -i \
      HOME="$scratch/home" TMPDIR="$scratch/tmp" PATH="${node%/*}:/usr/sbin:/usr/bin:/bin" \
      PLAYWRIGHT_BROWSERS_PATH="$scratch/playwright" WORLD_COMMIT="$commit" WORLD_HOST_NETNS="$netns" \
      /bin/bash "$repo/scripts/h5-capture/run-world-replay-isolated.sh" "$repo" "$scratch" "$evidence" "$@"
  ' -- "$runner_user" "$repo" "$scratch" "$evidence" "$GITHUB_SHA" "$host_netns" "$node_bin" "$@"
}
acquire="$repo/scripts/h5-capture/acquire-fresh-world-static.mjs"
snapshot="$scratch/fresh"
# Verify the runner's network isolation and browser transport before any H5 public GET.
run_isolated fresh-smoke
if [[ ${WORLD_BOOTSTRAP_SHAPE_ONLY:-0} == 1 ]]; then
  # One canonical public GET; never create a static snapshot, replay, or image.
  /usr/bin/env -i HOME="$scratch/home" TMPDIR="$scratch/tmp" \
    PATH="${node_bin%/*}:/usr/sbin:/usr/bin:/bin" \
    "$node_bin" "$acquire" inspect-bootstrap-shape
  exit 0
fi
node "$acquire" init "$snapshot" "$GITHUB_SHA" | tee "$evidence/fresh-init.json"
for round in {0..8}; do
  IFS= read -r draft_sha < "$snapshot/draft-$round.sha256"
  [[ "$draft_sha" =~ ^[a-f0-9]{64}$ ]]
  run_isolated fresh-probe "$draft_sha" "$round"
  probe="$evidence/probe-$round/report.json"
  cmp_sha=$(sha256sum "$probe" | cut -d ' ' -f 1)
  status=$(node -e 'console.log(JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8")).status)' "$probe")
  case "$status" in
    DISCOVERY_REQUIRED)
      node "$acquire" extend "$snapshot" "$round" "$draft_sha" "$probe" "$cmp_sha" | tee "$evidence/fresh-extend-$round.json";;
    DISCOVERY_CONVERGED)
      node "$acquire" seal "$snapshot" "$round" "$draft_sha" "$probe" "$cmp_sha" | tee "$evidence/fresh-seal.json"
      IFS= read -r seal_sha < "$snapshot/snapshot.sealed.sha256"
      [[ "$seal_sha" =~ ^[a-f0-9]{64}$ ]]
      run_isolated fresh-final "$seal_sha"
      exit 0;;
    *) echo 'Unexpected or blocked fresh probe' >&2; exit 1;;
  esac
done
exit 1
