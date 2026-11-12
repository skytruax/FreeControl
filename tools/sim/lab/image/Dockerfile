# SPDX-License-Identifier: GPL-3.0-only
# This one file is under the GNU GPL version 3 (see LICENSE-GPL-3.0.txt next to it), not the MIT
# licence of the rest of the repository: its blizzard-ui stage is adapted from the Dockerfile of
# wow-ui-sim (https://github.com/Osso/wow-ui-sim, GPL-3.0-only).
#
# wow-ui-sim, WoW Forever profile (client-wowforever, interface 16001), assembled from the
# PREBUILT upstream release package instead of compiling Rust.
#
# Build with ../build-image.sh (it fetches/verifies the inputs and passes the two named contexts):
#   pkg       the unpacked wow-ui-sim-v0.1.41-forever-linux-x86_64.tar.gz (sha256 verified)
#   upstream  anything that contains data/blizzard-ui-files/wowforever.txt from Osso/wow-ui-sim
#             at tag v0.1.41 (the list of Blizzard UI files this release expects)
#
# The release tarball does not contain Blizzard's UI source. The blizzard-ui stage below is the
# recipe from upstream's own Dockerfile (sparse checkout of Gethe/wow-ui-source at a pinned commit,
# verified against the manifest, plus the two marker files the simulator looks for) with one
# change: the commit. Upstream's Dockerfile still names ca8368f2... (1.60.1.70532), which fails its
# own manifest diff at v0.1.41; the commit pinned inside the release itself
# (data/blizzard-ui-builds/wowforever.json) is aff0d8cd... (1.60.1.70707) and matches exactly.

ARG BASE=ubuntu:26.04

# -----------------------------------------------------------------------------
# Blizzard UI source for Forever (Gethe/wow-ui-source, pinned commit)
# -----------------------------------------------------------------------------
FROM ${BASE} AS blizzard-ui
ARG GETHE_REVISION=aff0d8cd53bf4d9ef1c1dd2786b94461a276fb16
ARG UI_VERSION=1.60.1.70707
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=upstream data/blizzard-ui-files/wowforever.txt /tmp/manifests/wowforever.txt
RUN set -eu \
    && git init -q /wow-ui-source \
    && cd /wow-ui-source \
    && git remote add origin https://github.com/Gethe/wow-ui-source.git \
    && git fetch -q --depth=1 origin "$GETHE_REVISION" \
    && git sparse-checkout init --cone \
    && git sparse-checkout set Interface/AddOns \
    && git -c advice.detachedHead=false checkout -q --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "$GETHE_REVISION" \
    && git ls-tree -r --name-only HEAD Interface/AddOns/ | cut -d/ -f3- | LC_ALL=C sort > /tmp/actual.txt \
    && LC_ALL=C sort /tmp/manifests/wowforever.txt > /tmp/expected.txt \
    && diff -u /tmp/expected.txt /tmp/actual.txt \
    && while IFS= read -r entry; do test -f "Interface/AddOns/$entry" || exit 1; done < /tmp/manifests/wowforever.txt \
    && manifest_sha256="$(sha256sum /tmp/manifests/wowforever.txt | cut -d' ' -f1)" \
    && printf 'profile=%s\nversion=%s\nsource=gethe-image-build\ngethe_revision=%s\nmanifest_sha256=%s\nfallback=none\n' \
         wowforever "$UI_VERSION" "$GETHE_REVISION" "$manifest_sha256" \
         > Interface/AddOns/.wow-ui-sim-blizzard-ui-provenance \
    && touch Interface/AddOns/.wow-ui-sim-blizzard-ui-complete \
    && rm -rf /wow-ui-source/.git

# -----------------------------------------------------------------------------
# Drop DWARF debug sections from the release binaries (404 MB -> much smaller).
# Symbol tables are kept so panic backtraces still carry function names.
# -----------------------------------------------------------------------------
FROM ${BASE} AS slim
RUN apt-get update && apt-get install -y --no-install-recommends binutils \
    && rm -rf /var/lib/apt/lists/*
COPY --from=pkg wow-sim wow-cli /in/
RUN mkdir /out \
    && strip --strip-debug -o /out/wow-sim /in/wow-sim \
    && strip --strip-debug -o /out/wow-cli /in/wow-cli \
    && chmod 0755 /out/wow-sim /out/wow-cli \
    && ls -la /in /out

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
FROM ${BASE}
# NEEDED by the release binary (readelf -d): libicui18n.so.78 libicuuc.so.78 libasound.so.2
# libssl.so.3 libcrypto.so.3 libgcc_s.so.1 + glibc >= 2.43. Vulkan loader + Mesa lavapipe
# give the software renderer used by `screenshot`. DejaVu is the text fallback font.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libicu78 libasound2t64 libssl3t64 libgcc-s1 \
      libvulkan1 mesa-vulkan-drivers \
      fonts-dejavu-core ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=slim /out/wow-sim /out/wow-cli /app/
COPY --from=pkg Interface/ /app/Interface/
COPY --from=pkg spells/ /app/spells/
COPY --from=pkg README.md LICENSE /app/

# The simulator resolves its caches through dirs::cache_dir() => $XDG_CACHE_HOME or $HOME/.cache.
# Use a dedicated HOME that any uid can use, so the container can run as the host user
# (--user) and still write its scratch caches into the throwaway container layer.
ENV HOME=/simhome \
    XDG_CACHE_HOME=/simhome/.cache \
    XDG_CONFIG_HOME=/simhome/.config \
    XDG_DATA_HOME=/simhome/.local/share
COPY --from=blizzard-ui /wow-ui-source/Interface/AddOns/ /simhome/.cache/wow-ui-sim/blizzard-ui/wowforever/AddOns/

# Pre-warm the Lua bytecode cache for the 272 Blizzard addons (saves ~0.8 s per run) and prove at
# build time, with networking off, that the stock Forever UI starts with zero Lua errors.
# run-sim.sh mounts the root filesystem read-only, so this cache is never modified at run time.
RUN --network=none set -eu \
    && WOW_SIM_NO_SAVED_VARS=1 WOW_SIM_NO_SOUND=1 WOW_SIM_CASC=0 \
       /app/wow-sim --no-addons --no-saved-vars lua-errors > /tmp/prewarm.json 2> /tmp/prewarm.log \
    && grep -q 'Status: CLEAN' /tmp/prewarm.log \
    && test "$(tr -d '[:space:]' < /tmp/prewarm.json)" = "[]" \
    && rm -rf /simhome/.local /simhome/.config /tmp/prewarm.* \
    && mkdir -p /simhome/.config /simhome/.local/share /out /addons \
    && chmod -R a+rX /simhome \
    && chmod 1777 /simhome/.config /simhome/.local /simhome/.local/share /out

# Test-support helper (SimInput): an early-loading helper addon plus its secure bootstrap.
# Only used when run-sim.sh asks for it; see simlib/AddOns/!SimInput/SimInput.lua.
COPY simlib/ /simlib/

# No WTF directory, no sound device, no GPU, no game install in the image.
ENV WOW_SIM_NO_SAVED_VARS=1 \
    WOW_SIM_SOFTWARE_RENDER=1 \
    WOW_SIM_NO_SOUND=1 \
    WOW_SIM_CASC=0

ENTRYPOINT ["/app/wow-sim"]
