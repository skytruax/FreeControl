#!/usr/bin/env bash
# run-sim.sh - load a World of Warcraft: Forever addon (interface 16001) WITHOUT the game.
#
# What it does, for the addon folder you pass:
#   0. STATIC  (advice only) reads the addon's Lua and flags API/CVar/event names that are missing
#              in the real client, or that exist in only one of client and simulator (tools/api_lint.py).
#   1. LOAD    loads the addon next to the full Blizzard Forever UI (272 Blizzard addons, 1.60.1.70707),
#              fires the login sequence (ADDON_LOADED, VARIABLES_LOADED, PLAYER_LOGIN,
#              PLAYER_ENTERING_WORLD, ...), then advances simulated time so delayed C_Timer / OnUpdate
#              code runs too. Every Lua error raised along the way is reported.
#   2. TESTS   runs <addon>/tests/*.lua (if any) with the simulator's test runner.
#   3. SHOT    renders the UI headless (software Vulkan) to <out>/screenshot.png.
#
# Exit status
#   0  no Lua errors, no failed tests (and the screenshot was written, unless --no-screenshot)
#   1  Lua errors while loading/logging in, failed tests, or Lua errors reported while tests ran
#   2  usage or infrastructure problem (bad path, Docker/image missing, simulator crashed)
#   3  only the screenshot failed
#
# How long a run takes (22-core Linux box, image already built, measured 2026-11-12):
#   5 to 6 seconds wall clock for everything; the three phases run in parallel
#   (LOAD ~3.7 s, TESTS ~4.8 s for SimProbe's 51 tests, SHOT ~4.3 s; ~13 s one after another).
#   Almost all of it is the simulator loading Blizzard's UI (~2.3 s) and starting up; your addon
#   and its tests add milliseconds. Building the image from scratch takes about 25 s.
#
# Sandbox: each phase is its own throw-away container with
#   --network none, --read-only root, --cap-drop ALL, no-new-privileges, non-root (your uid),
#   memory/pid limits, and only two bind mounts: the addon folder (read-only) and, for the
#   screenshot phase only, the output folder (--with adds more read-only addon folders).
#   Nothing from the simulator runs on the host. It needs no network at run time.
#   This matters: the simulator's Lua exposes io.* and os.execute to addon code.
#
# Usage
#   run-sim.sh [options] /path/to/MyAddon
#
# Options
#   -o, --out DIR          where logs and the screenshot go   (default: <this folder>/out/<AddonName>)
#       --with DIR         also load this addon folder (a dependency), mounted read-only; repeatable
#       --no-tests         skip phase 2
#       --no-screenshot    skip phase 3
#       --scenario FILE    Lua run after login and before the screenshot (ordinary insecure addon
#                          code: show frames, A_Admin.SetActionSlot(...), etc.)
#                          default: <addon>/tests/sim/screenshot.lua when it exists
#       --size WxH         screenshot size in pixels            (default 1600x1200)
#       --crop WxH+X+Y     crop the screenshot
#       --filter NAME      render only the frame subtree whose name contains NAME
#       --settle SECONDS   simulated seconds to run after login in phase 1 (default 3, 0 = off)
#       --class NAME       player class (default Paladin)   --race NAME   player race
#       --solo             no demo party (the simulator starts with 4 fake party members)
#       --siminput MODE    auto|on|off: load the SimInput test helper (secure-origin clicks and
#                          CLICK-binding key presses). auto = on when a test mentions "SimInput".
#       --allow-test-lua-errors   do not fail when tests pass but Lua errors were reported meanwhile
#       --env KEY=VALUE    extra environment variable for the simulator (repeatable)
#   -v, --verbose          print the full simulator logs
#   -h, --help
#
# Environment
#   SIM_IMAGE              image to use (default simlab/wow-ui-sim-forever:0.1.41, see build-image.sh)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${SIM_IMAGE:-simlab/wow-ui-sim-forever:0.1.41}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { echo "run-sim.sh: $*" >&2; exit 2; }

out_dir=""
run_tests=1
run_shot=1
scenario=""
size="1600x1200"
crop=""
filter=""
settle="3"
class=""
race=""
solo=0
siminput="auto"
allow_test_errors=0
verbose=0
extra_env=()
with_dirs=()
addon_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) [[ $# -ge 2 ]] || die "$1 needs a value"; out_dir="$2"; shift 2 ;;
    --with) [[ $# -ge 2 ]] || die "$1 needs a value"; with_dirs+=("$2"); shift 2 ;;
    --no-tests) run_tests=0; shift ;;
    --no-screenshot) run_shot=0; shift ;;
    --scenario) [[ $# -ge 2 ]] || die "$1 needs a value"; scenario="$2"; shift 2 ;;
    --size) [[ $# -ge 2 ]] || die "$1 needs a value"; size="$2"; shift 2 ;;
    --crop) [[ $# -ge 2 ]] || die "$1 needs a value"; crop="$2"; shift 2 ;;
    --filter) [[ $# -ge 2 ]] || die "$1 needs a value"; filter="$2"; shift 2 ;;
    --settle) [[ $# -ge 2 ]] || die "$1 needs a value"; settle="$2"; shift 2 ;;
    --class) [[ $# -ge 2 ]] || die "$1 needs a value"; class="$2"; shift 2 ;;
    --race) [[ $# -ge 2 ]] || die "$1 needs a value"; race="$2"; shift 2 ;;
    --solo) solo=1; shift ;;
    --siminput) [[ $# -ge 2 ]] || die "$1 needs a value"; siminput="$2"; shift 2 ;;
    --allow-test-lua-errors) allow_test_errors=1; shift ;;
    --env) [[ $# -ge 2 ]] || die "$1 needs a value"; extra_env+=("$2"); shift 2 ;;
    -v|--verbose) verbose=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; [[ $# -gt 0 ]] && addon_arg="$1"; break ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) [[ -z "$addon_arg" ]] || die "only one addon folder may be given"; addon_arg="$1"; shift ;;
  esac
done

[[ -n "$addon_arg" ]] || { usage >&2; exit 2; }
[[ -d "$addon_arg" ]] || die "not a directory: $addon_arg"
addon_dir="$(cd "$addon_arg" && pwd -P)"
addon_name="$(basename "$addon_dir")"
[[ "$addon_name" =~ ^[A-Za-z0-9_!.-]+$ ]] || die "addon folder name '$addon_name' has characters I will not pass to docker"

with_mounts=()
for d in "${with_dirs[@]}"; do
  [[ -d "$d" ]] || die "--with: not a directory: $d"
  dep_dir="$(cd "$d" && pwd -P)"
  dep_name="$(basename "$dep_dir")"
  [[ "$dep_name" =~ ^[A-Za-z0-9_!.-]+$ ]] || die "--with: folder name '$dep_name' has characters I will not pass to docker"
  [[ "$dep_name" != "$addon_name" ]] || die "--with: $dep_name is the addon under test"
  with_mounts+=(-v "$dep_dir:/addons/$dep_name:ro")
done

shopt -s nullglob
tocs=("$addon_dir"/*.toc)
[[ ${#tocs[@]} -gt 0 ]] || die "no .toc file in $addon_dir (is this the addon folder itself?)"
toc_match=0
for toc in "${tocs[@]}"; do
  base="$(basename "$toc" .toc)"
  [[ "$base" == "$addon_name" || "$base" == "$addon_name"[_-]* ]] && toc_match=1
done
warnings=()
[[ $toc_match -eq 1 ]] || warnings+=("no TOC named $addon_name.toc: the client only loads a TOC whose name matches its folder")
grep -Eqs '^## *Interface:.*\b16001\b' "${tocs[@]}" || warnings+=("no TOC lists '## Interface: 16001': the Forever client will flag the addon as out of date")
[[ "$size" =~ ^([0-9]+)x([0-9]+)$ ]] || die "--size must look like 1600x1200"
width="${BASH_REMATCH[1]}"; height="${BASH_REMATCH[2]}"
[[ "$settle" =~ ^[0-9]+$ ]] || die "--settle must be a whole number of seconds"
case "$siminput" in auto|on|off) ;; *) die "--siminput must be auto, on or off" ;; esac

# Files the TOC lists must exist: the client reports a missing one, the simulator only bumps a
# silent warning counter.
toc_missing=()
for toc in "${tocs[@]}"; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    path="${line%%[[:space:]]\[*}"                 # drop a trailing " [AllowLoad...]" condition
    path="${path%"${path##*[![:space:]]}"}"        # right-trim
    [[ -z "$path" || "$path" == *"["* ]] && continue  # [Family]/[Game]/[TextLocale] path variables
    rel="${path//\\//}"
    if [[ ! -e "$addon_dir/$rel" ]]; then
      other_case="$(find "$addon_dir" -ipath "$addon_dir/$rel" -print -quit 2>/dev/null || true)"
      if [[ -n "$other_case" ]]; then
        warnings+=("$(basename "$toc") lists '$path' but the file on disk is '${other_case#"$addon_dir"/}' (case differs: fine on Windows/macOS, not on a case-sensitive filesystem)")
      else
        toc_missing+=("$(basename "$toc") lists '$path' but that file does not exist")
      fi
    fi
  done < "$toc"
done

command -v docker >/dev/null || die "docker not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image $IMAGE not found - build it with: $here/build-image.sh"

# Things that exist in the simulator's Lua but not in the game client.
lua_files=()
while IFS= read -r -d '' f; do lua_files+=("$f"); done < <(find "$addon_dir" -name '*.lua' -not -path "$addon_dir/tests/*" -print0)
if [[ ${#lua_files[@]} -gt 0 ]]; then
  hits="$(grep -EnH '(^|[^A-Za-z0-9_.:])(io|os|package)\.[A-Za-z_]+' "${lua_files[@]}" 2>/dev/null | grep -Ev '^[^:]+:[0-9]+:\s*--' | head -5 || true)"
  [[ -z "$hits" ]] || warnings+=("addon code uses io./os./package. - these exist in the simulator but NOT in the WoW client:"$'\n'"$(sed 's/^/        /' <<<"$hits")")
fi

test_files=()
if [[ -d "$addon_dir/tests" ]]; then test_files=("$addon_dir"/tests/*.lua); fi
[[ $run_tests -eq 1 && ${#test_files[@]} -eq 0 ]] && run_tests=0 && no_tests_note="no tests/*.lua"

use_siminput=0
if [[ $run_tests -eq 1 ]]; then
  case "$siminput" in
    on) use_siminput=1 ;;
    auto) grep -qs 'SimInput' "${test_files[@]}" && use_siminput=1 || true ;;
  esac
fi

if [[ -z "$scenario" && -f "$addon_dir/tests/sim/screenshot.lua" ]]; then scenario="$addon_dir/tests/sim/screenshot.lua"; fi
scenario_code=""
if [[ -n "$scenario" ]]; then
  [[ -f "$scenario" ]] || die "scenario file not found: $scenario"
  [[ $(stat -c %s "$scenario") -le 100000 ]] || die "scenario file is larger than 100 kB"
  scenario_code="$(cat "$scenario")"
fi

[[ -n "$out_dir" ]] || out_dir="$here/out/$addon_name"
mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd -P)"
rm -f "$out_dir"/{lua-errors.json,load.log,tests.log,screenshot.log,screenshot.png,result.txt}

# ---------------------------------------------------------------------------------------------
# One sandboxed simulator invocation. $1 = "out" to mount the output folder, anything else = no.
# ---------------------------------------------------------------------------------------------
sim() {
  local mount_out="$1"; shift
  local args=(run --rm --network none --read-only
    --cap-drop ALL --security-opt no-new-privileges
    --pids-limit 512 --memory 6g
    --tmpfs /tmp:rw,mode=1777,size=256m
    --tmpfs /simhome/.local:rw,mode=1777,size=64m
    --tmpfs /simhome/.config:rw,mode=1777,size=8m
    --user "$(id -u):$(id -g)"
    -e WOW_SIM_LUA_ERRORS_BY_ADDON=1 -e MESA_SHADER_CACHE_DISABLE=true
    -e "WOW_SIM_MAX_CORES=$ncpu"
    -v "$addon_dir:/addons/$addon_name:ro")
  args+=("${with_mounts[@]}")
  [[ "$mount_out" == "out" ]] && args+=(-v "$out_dir:/out")
  [[ $solo -eq 1 ]] && args+=(-e WOW_SIM_NO_PARTY=1)
  local kv
  for kv in "${extra_env[@]}"; do args+=(-e "$kv"); done
  docker "${args[@]}" "$IMAGE" "$@"
}

common=(--addons-path /addons --no-saved-vars)
[[ -n "$class" ]] && common+=(--class "$class")
[[ -n "$race" ]] && common+=(--race "$race")

# wow-sim pins itself to host CPUs 0..N-1 (default N=2). Three parallel phases would then share
# two cores, so let it use every core the host has.
ncpu="$(nproc 2>/dev/null || echo 2)"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1fs", b - a }'; }

t0="$(now)"

# Phase 1: load + login + settle. stdout is the JSON list of unique Lua errors.
(
  s="$(now)"
  load_args=("${common[@]}")
  if [[ "$settle" -gt 0 ]]; then
    # Secure so that timers/OnUpdate handlers are dispatched from an untainted stack, as the client does.
    load_args+=(--exec-lua-secure "--exec-lua=A_Admin.SetManualClock(GetTime()); for i = 1, $((settle * 10)) do A_Admin.AdvanceTime(0.1) end")
  fi
  rc=0
  sim no "${load_args[@]}" lua-errors > "$out_dir/lua-errors.json" 2> "$out_dir/load.log" || rc=$?
  echo "$rc $(elapsed "$s" "$(now)")" > "$out_dir/.load.rc"
) &
pid_load=$!

# Phase 2: tests.
pid_tests=""
if [[ $run_tests -eq 1 ]]; then
  (
    s="$(now)"
    test_args=()
    [[ $use_siminput -eq 1 ]] && test_args+=(--addons-path /simlib/AddOns --exec-lua-secure "--exec-lua=@/simlib/siminput_secure.lua")
    test_args+=("${common[@]}")
    rc=0
    sim no "${test_args[@]}" run-tests "$addon_name" > "$out_dir/tests.log" 2>&1 || rc=$?
    echo "$rc $(elapsed "$s" "$(now)")" > "$out_dir/.tests.rc"
  ) &
  pid_tests=$!
fi

# Phase 3: screenshot.
pid_shot=""
if [[ $run_shot -eq 1 ]]; then
  (
    s="$(now)"
    shot_args=("${common[@]}")
    # "--exec-lua=CODE": the = form is required, Lua code may start with "--" (a comment).
    [[ -n "$scenario_code" ]] && shot_args+=("--exec-lua=$scenario_code")
    shot_args+=(screenshot --png -o /out/screenshot.png --width "$width" --height "$height")
    [[ -n "$crop" ]] && shot_args+=(--crop "$crop")
    [[ -n "$filter" ]] && shot_args+=(--filter "$filter")
    rc=0
    sim out "${shot_args[@]}" > "$out_dir/screenshot.log" 2>&1 || rc=$?
    echo "$rc $(elapsed "$s" "$(now)")" > "$out_dir/.shot.rc"
  ) &
  pid_shot=$!
fi

wait "$pid_load" || true
[[ -n "$pid_tests" ]] && { wait "$pid_tests" || true; }
[[ -n "$pid_shot" ]] && { wait "$pid_shot" || true; }
wall="$(elapsed "$t0" "$(now)")"

read -r load_rc load_time < "$out_dir/.load.rc"; rm -f "$out_dir/.load.rc"
tests_rc=0; tests_time="-"
[[ -n "$pid_tests" ]] && { read -r tests_rc tests_time < "$out_dir/.tests.rc"; rm -f "$out_dir/.tests.rc"; }
shot_rc=0; shot_time="-"
[[ -n "$pid_shot" ]] && { read -r shot_rc shot_time < "$out_dir/.shot.rc"; rm -f "$out_dir/.shot.rc"; }

# ---------------------------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------------------------
status=0
infra=0
report() { printf '%s\n' "$*" | tee -a "$out_dir/result.txt"; }

report "wow-ui-sim / WoW Forever (interface 16001) / image $IMAGE"
report "addon: $addon_name  ($addon_dir)"
for w in "${warnings[@]}"; do report "  WARN  $w"; done
if [[ ${#toc_missing[@]} -gt 0 ]]; then
  report "[0] TOC    FAILED - ${#toc_missing[@]} listed file(s) missing (the simulator skips them silently, the client reports an error):"
  for m in "${toc_missing[@]}"; do report "         $m"; done
  status=1
fi

# -- static API cross-check (advice only, never changes the exit status)
if [[ -f "$here/tools/api_lint.py" ]] && command -v python3 >/dev/null; then
  lint="$(python3 -I "$here/tools/api_lint.py" "$addon_dir" 2>&1 || true)"
  if grep -q 'nothing to report' <<<"$lint"; then
    report "[0] STATIC $(head -n1 <<<"$lint" | sed 's/^api_lint: //') - nothing to report"
  else
    report "[0] STATIC $(head -n1 <<<"$lint" | sed 's/^api_lint: //')"
    tail -n +2 <<<"$lint" | sed 's/^/       /' | tee -a "$out_dir/result.txt"
  fi
fi

# -- phase 1
loaded_line="$(grep -m1 -E '^Loaded: [0-9]+/[0-9]+ addons' "$out_dir/load.log" || true)"
if ! grep -q '=== Final observed Lua error summary ===' "$out_dir/load.log"; then
  report "[1] LOAD   CRASHED - the simulator did not finish (exit $load_rc, $load_time). Last lines of $out_dir/load.log:"
  tail -n 15 "$out_dir/load.log" | sed 's/^/         /' | tee -a "$out_dir/result.txt"
  infra=1
else
  # Each error is listed twice (raw + Blizzard's 'Lua Error:' re-report); show each once.
  summary="$(python3 -I - "$out_dir/lua-errors.json" <<'PY'
import json, sys
try:
    errors = json.load(open(sys.argv[1]))
except Exception as exc:  # stdout was not the expected JSON
    print(f"UNPARSEABLE {exc}")
    sys.exit(0)
seen, unique = set(), []
for err in errors:
    msg = err.get("message", "")
    key = msg
    while key.startswith(("Lua Error: ", "Lua error: ")):
        key = key[len("Lua Error: "):]
    first = key.splitlines()[0] if key else ""
    if first in seen:
        continue
    seen.add(first)
    unique.append((first, key, err.get("count", 1)))
print(len(unique))
for first, full, count in unique:
    print(f"  x{count}  {first}")
    for line in full.splitlines()[1:7]:
        print(f"         {line.strip()}")
PY
)"
  count="$(head -n1 <<<"$summary")"
  if [[ "$count" == UNPARSEABLE* ]]; then
    report "[1] LOAD   could not read $out_dir/lua-errors.json ($count)"; infra=1
  elif [[ "$count" == "0" && "$load_rc" == "0" ]]; then
    report "[1] LOAD   CLEAN - 0 Lua errors during load, login and ${settle}s of simulated time   (${loaded_line:-addon loaded})   $load_time"
  else
    report "[1] LOAD   FAILED - $count distinct Lua error(s) during load/login/${settle}s settle   (${loaded_line:-?})   $load_time"
    tail -n +2 <<<"$summary" | tee -a "$out_dir/result.txt"
    grep -A20 -m1 '^\[lua-errors\] errors by addon:' "$out_dir/load.log" | grep -E '^  [^ ].*: [0-9]+ error' | sed 's/^/       by addon:/' | tee -a "$out_dir/result.txt" || true
    status=1
  fi
  if grep -q 'Loaded: 0/' "$out_dir/load.log"; then
    report "       the addon itself was NOT loaded - check the TOC"; status=1
  fi
fi

# -- phase 2
if [[ -n "$pid_tests" ]]; then
  tests_line="$(sed 's/\x1b\[[0-9;]*m//g' "$out_dir/tests.log" | grep -E '^[0-9]+ tests, [0-9]+ passed, [0-9]+ failed' | tail -n1 || true)"
  test_errors="$(grep -E '^Lua error: ' "$out_dir/tests.log" | sed -E 's/^(Lua [Ee]rror: )+//' | sort -u || true)"
  n_test_errors=0; [[ -n "$test_errors" ]] && n_test_errors="$(wc -l <<<"$test_errors")"
  helper=""; [[ $use_siminput -eq 1 ]] && helper="  [SimInput helper loaded]"
  if [[ -z "$tests_line" ]]; then
    report "[2] TESTS  CRASHED - no test summary (exit $tests_rc, $tests_time). Last lines of $out_dir/tests.log:"
    sed 's/\x1b\[[0-9;]*m//g' "$out_dir/tests.log" | tail -n 15 | sed 's/^/         /' | tee -a "$out_dir/result.txt"
    infra=1
  elif [[ "$tests_rc" != "0" ]]; then
    report "[2] TESTS  FAILED - $tests_line   $tests_time$helper"
    sed 's/\x1b\[[0-9;]*m//g' "$out_dir/tests.log" | grep -A1 -E '^  ✗ ' | grep -v '^--$' | sed 's/^/       /' | tee -a "$out_dir/result.txt"
    status=1
  else
    report "[2] TESTS  PASSED - $tests_line   $tests_time$helper"
  fi
  if [[ $n_test_errors -gt 0 ]]; then
    if [[ $allow_test_errors -eq 1 ]]; then
      report "       note: $n_test_errors distinct Lua error(s) were reported while tests ran (allowed by --allow-test-lua-errors)"
    else
      report "       FAILED - $n_test_errors distinct Lua error(s) were reported while tests ran (they do not fail a test by themselves):"
      head -n 8 <<<"$test_errors" | cut -c1-300 | sed 's/^/         /' | tee -a "$out_dir/result.txt"
      status=1
    fi
  fi
else
  report "[2] TESTS  skipped (${no_tests_note:---no-tests})"
fi

# -- phase 3
shot_failed=0
if [[ -n "$pid_shot" ]]; then
  if [[ "$shot_rc" == "0" && -s "$out_dir/screenshot.png" ]]; then
    missing="$(grep -c "Not found: Interface.AddOns.$addon_name" "$out_dir/screenshot.log" || true)"
    report "[3] SHOT   $out_dir/screenshot.png   $(grep -o 'Saved [0-9x]* screenshot' "$out_dir/screenshot.log" | head -n1)   $shot_time"
    if [[ "$missing" != "0" ]]; then
      report "       WARN  $missing texture path(s) inside the addon could not be loaded:"
      grep "Not found: Interface.AddOns.$addon_name" "$out_dir/screenshot.log" | sed -E 's/^\[[^]]*\] \[TexMgr\] /         /' | sort -u | head -n 10 | tee -a "$out_dir/result.txt"
    fi
    if grep -q '^\[exec-lua\] error' "$out_dir/screenshot.log"; then
      report "       WARN  the scenario script raised an error:"
      grep -A3 '^\[exec-lua\] error' "$out_dir/screenshot.log" | head -n 6 | sed 's/^/         /' | tee -a "$out_dir/result.txt"
    fi
  else
    report "[3] SHOT   FAILED (exit $shot_rc, $shot_time). Last lines of $out_dir/screenshot.log:"
    tail -n 12 "$out_dir/screenshot.log" | sed 's/^/         /' | tee -a "$out_dir/result.txt"
    shot_failed=1
  fi
else
  report "[3] SHOT   skipped (--no-screenshot)"
fi

if [[ $verbose -eq 1 ]]; then
  for f in load.log tests.log screenshot.log; do
    [[ -f "$out_dir/$f" ]] && { echo "----- $out_dir/$f"; sed 's/\x1b\[[0-9;]*m//g' "$out_dir/$f"; }
  done
fi

final=0
if [[ $infra -eq 1 ]]; then final=2
elif [[ $status -eq 1 ]]; then final=1
elif [[ $shot_failed -eq 1 ]]; then final=3
fi
case $final in
  0) report "RESULT: PASS   (wall $wall, logs in $out_dir)" ;;
  1) report "RESULT: FAIL   (wall $wall, logs in $out_dir)" ;;
  2) report "RESULT: ERROR - the simulator itself did not complete   (wall $wall, logs in $out_dir)" ;;
  3) report "RESULT: PASS for Lua/tests, but no screenshot   (wall $wall, logs in $out_dir)" ;;
esac
exit $final
