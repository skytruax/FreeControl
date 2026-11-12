#!/usr/bin/env bash
# One-time setup for the simulator tests: fetches the pinned inputs, checks every one against a
# known sha256, and builds the Docker image run-sim.sh uses. Safe to run again; anything already
# downloaded and intact is reused.
#
#   tools/sim/lab/build-image.sh [extra docker build options, e.g. --no-cache]
#
# What it fetches (about 180 MB, kept in ${XDG_CACHE_HOME:-~/.cache}/freecontrol-sim):
#   * the prebuilt WoW Forever release of wow-ui-sim (github.com/Osso/wow-ui-sim, GPL-3.0)
#   * that release's list of Blizzard UI files, used to verify the UI source the image fetches
#   * wowless's API, CVar and event lists for the Forever client (github.com/wowless/wowless,
#     MIT), which the static check in run-sim.sh compares the addon against. These three small
#     files go next to this script, in dl-wowless-wowf-data/.
# The image build itself also pulls ubuntu:26.04 and Blizzard's interface source for build
# 1.60.1.70707 from github.com/Gethe/wow-ui-source at a pinned commit.
#
# Nothing downloaded is run on this machine: the release is only unpacked, and Docker copies it
# into the image. Needs Docker 23 or newer (named build contexts), curl, tar and sha256sum.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="${FREECONTROL_SIM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/freecontrol-sim}"
image="${SIM_IMAGE:-simlab/wow-ui-sim-forever:0.1.41}"

version="0.1.41"
package="wow-ui-sim-v${version}-forever-linux-x86_64"
package_sha256="6958e8c0b6e24d56970637996a5dd4a0c97c39462542b13a673263eec81a8fff"
manifest_sha256="55e3e3846c9dc112f4a593d2d854ba78f210739e5ada9a176785883b4d735264"
wowless_commit="c16e98ff75e83871553765dea4ab7674f161696d"

# fetch URL FILE SHA256: download unless FILE is already there with the right checksum.
fetch() {
  local url="$1" file="$2" sha="$3"
  if [[ -f "$file" ]] && echo "$sha  $file" | sha256sum --check --status; then
    return
  fi
  echo "fetching $url"
  mkdir -p "$(dirname "$file")"
  curl --fail --silent --show-error --location --output "$file.part" "$url"
  echo "$sha  $file.part" | sha256sum --check --status || {
    echo "checksum mismatch for $url (left at $file.part)" >&2
    exit 1
  }
  mv "$file.part" "$file"
}

fetch "https://github.com/Osso/wow-ui-sim/releases/download/v${version}/${package}.tar.gz" \
  "$cache/release/${package}.tar.gz" "$package_sha256"
fetch "https://raw.githubusercontent.com/Osso/wow-ui-sim/v${version}/data/blizzard-ui-files/wowforever.txt" \
  "$cache/upstream/data/blizzard-ui-files/wowforever.txt" "$manifest_sha256"
fetch "https://raw.githubusercontent.com/wowless/wowless/${wowless_commit}/data/products/wowf/apis.yaml" \
  "$here/dl-wowless-wowf-data/apis.yaml" "1de4e109282d5a5631be6f2235e94dded328be1f896bdf73a35a512143f09efd"
fetch "https://raw.githubusercontent.com/wowless/wowless/${wowless_commit}/data/products/wowf/cvars.yaml" \
  "$here/dl-wowless-wowf-data/cvars.yaml" "b9d35115b6ae94914d16ea3d375f56122bdb89d33d633a90ab7d9f9297783fe4"
fetch "https://raw.githubusercontent.com/wowless/wowless/${wowless_commit}/data/products/wowf/events.yaml" \
  "$here/dl-wowless-wowf-data/events.yaml" "2eff52112a3b2d3c0dbedb46a5ec4ba14790731c6d63cde646bf3b65e0670d3e"

# Unpack into a directory named after the checksum, so an unpacked copy always matches the
# archive it came from and a half-finished unpack is never mistaken for a complete one.
unpacked="$cache/release/unpacked-${package_sha256:0:12}"
if [[ ! -f "$unpacked/.complete" ]]; then
  mkdir -p "$unpacked"
  tar --extract --gzip --no-same-owner --file "$cache/release/${package}.tar.gz" --directory "$unpacked"
  touch "$unpacked/.complete"
fi
[[ -f "$unpacked/$package/wow-sim" ]] || { echo "release package has no wow-sim in $unpacked/$package" >&2; exit 1; }

docker build \
  --tag "$image" \
  --build-context "pkg=$unpacked/$package" \
  --build-context "upstream=$cache/upstream" \
  "$@" \
  "$here/image"

echo "built $image; run the tests with tools/sim/run.sh"
