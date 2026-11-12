#!/usr/bin/env bash
# Loads FreeControl next to Blizzard's real Forever interface code in the wow-ui-sim simulator
# (https://github.com/Osso/wow-ui-sim), runs tools/sim/tests against it, and takes a screenshot.
#
#   tools/sim/lab/build-image.sh     # once: fetch the simulator and build its Docker image
#   tools/sim/run.sh                 # about six seconds; logs in tools/sim/out/
#   tools/sim/run.sh --no-screenshot # any option of lab/run-sim.sh can be passed through
#
# Everything runs in throw-away containers with no network. This script only makes a scratch copy
# of the addon with the test files added, so the folder you ship stays free of them.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$root/FreeControl" "$work/FreeControl"
cp -r "$here/tests" "$work/FreeControl/tests"

out="${SIM_OUT:-$here/out}"
mkdir -p "$out"
status=0
"$here/lab/run-sim.sh" --solo -o "$out" "$@" "$work/FreeControl" || status=$?

# Keep the latest picture of a passing run where the README shows it.
if [[ $status -eq 0 && -s "$out/screenshot.png" ]]; then
  cp "$out/screenshot.png" "$root/docs/sim-screenshot.png"
fi
exit "$status"
