#!/usr/bin/env python3
"""Static cross-check of an addon's API use against (a) the real Forever client and (b) the simulator.

The simulator implements only about half of the client's C API, and it also carries functions the
Forever client does not have. So a clean simulator run can hide a call that is nil in the game, and
a simulator error can be about a function that exists in the game. This script reads the addon's
Lua source (it does not run it) and sorts every API reference into:

  NOT IN CLIENT   referenced, but absent from the client API list   -> nil in the game (typo / retail-only)
  SIM ONLY        absent from the client list but present in the simulator -> passes here, breaks in game
  SIM GAP         in the client list but missing in the simulator    -> errors here only; stub it in tests

Also checks GetCVar/SetCVar names and RegisterEvent names given as string literals.

Reference data
  client     dl-wowless-wowf-data/{apis,cvars,events}.yaml : wowless's `wowf` product data
             (github.com/wowless/wowless, MIT), build 1.60.1.70888. I did not verify how wowless
             produced these files; treat them as a good but third-party description of the client.
  simulator  meta/sim-api-surface.txt : enumerated from the running image by tools/dump-api-surface.sh

Usage: python3 -I tools/api_lint.py /path/to/Addon [--all]
       (--all also lists the SIM GAP references that are plain global functions)
Exit status is always 0: this is advice, not a gate.
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
CLIENT_DIR = HERE / "dl-wowless-wowf-data"
SIM_SURFACE = HERE / "meta" / "sim-api-surface.txt"

KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_.]*):\s*$")


def yaml_top_keys(path):
    """Top-level mapping keys of a wowless data file (they sit in column 0)."""
    keys = {}
    current = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = KEY.match(line)
        if m:
            current = m.group(1)
            keys[current] = {}
        elif current and line.startswith("  default:"):
            keys[current]["default"] = line.split(":", 1)[1].strip().strip("'\"")
    return keys


def strip_comments_and_strings(src):
    """Blank out Lua comments. Strings are kept (CVar/event names live in them)."""
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_all = "--all" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    addon = pathlib.Path(args[0]).resolve()
    for needed in (CLIENT_DIR / "apis.yaml", SIM_SURFACE):
        if not needed.exists():
            print(f"api_lint: reference data missing ({needed}); skipping")
            return

    client = set(yaml_top_keys(CLIENT_DIR / "apis.yaml"))
    cvars = yaml_top_keys(CLIENT_DIR / "cvars.yaml") if (CLIENT_DIR / "cvars.yaml").exists() else {}
    events = set(yaml_top_keys(CLIENT_DIR / "events.yaml")) if (CLIENT_DIR / "events.yaml").exists() else set()
    sim = {line.strip() for line in SIM_SURFACE.read_text().splitlines() if line.strip()}
    client_namespaces = {name.split(".", 1)[0] for name in client if "." in name}

    files = sorted(p for p in addon.rglob("*.lua") if "tests" not in p.relative_to(addon).parts)
    refs = {}       # name -> first "file:line"
    cvar_refs = {}
    event_refs = {}
    defined = set()
    for path in files:
        text = strip_comments_and_strings(path.read_text(encoding="utf-8", errors="replace"))
        rel = path.relative_to(addon)
        for lineno, line in enumerate(text.splitlines(), 1):
            where = f"{rel}:{lineno}"
            for m in re.finditer(r"\b(C_[A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)", line):
                refs.setdefault(f"{m.group(1)}.{m.group(2)}", where)
            for m in re.finditer(r"(?<![.:\w])([A-Za-z_][A-Za-z0-9_]*)\s*\(", line):
                refs.setdefault(m.group(1), where)
            for m in re.finditer(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(|\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)|\blocal\s+([A-Za-z_][A-Za-z0-9_, ]*?)\s*(?:=|$)|^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", line):
                for group in m.groups():
                    if group:
                        defined.update(part.strip() for part in group.split(","))
            for m in re.finditer(r"\b(?:Get|Set)CVar(?:Bool|Default|Info|Bitfield)?\s*\(\s*[\"']([A-Za-z0-9_.]+)[\"']", line):
                cvar_refs.setdefault(m.group(1), where)
            for m in re.finditer(r":(?:RegisterEvent|RegisterUnitEvent)\s*\(\s*[\"']([A-Z0-9_]+)[\"']", line):
                event_refs.setdefault(m.group(1), where)

    not_in_client, sim_only, sim_gap_ns, sim_gap_global = [], [], [], []
    lua_keywords = {"if", "while", "for", "function", "return", "and", "or", "not", "elseif", "until", "local", "in"}
    for name, where in sorted(refs.items()):
        if "." in name:
            namespace = name.split(".", 1)[0]
            if name in client:
                if name not in sim:
                    sim_gap_ns.append((name, where))
            elif name in sim:
                sim_only.append((name, where))
            elif namespace in client_namespaces or namespace.startswith("C_"):
                not_in_client.append((name, where))
        elif name not in lua_keywords and name not in defined:
            if name in client and name not in sim:
                sim_gap_global.append((name, where))

    def section(title, rows, hint):
        if not rows:
            return
        print(f"  {title}: {len(rows)}   ({hint})")
        for name, where in rows[:25]:
            print(f"      {name:<58} {where}")
        if len(rows) > 25:
            print(f"      ... and {len(rows) - 25} more")

    print(f"api_lint: {len(files)} Lua file(s), {sum(1 for n in refs if '.' in n)} C_ references; "
          f"client list = wowless wowf 1.60.1.70888 ({len(client)} APIs), simulator = {len(sim)} functions")
    section("NOT IN CLIENT", not_in_client, "nil in the game: typo or an API the Forever client does not have")
    section("SIM ONLY", sim_only, "the simulator has it, the client list does not: passes here, breaks in game")
    section("SIM GAP", sim_gap_ns + (sim_gap_global if show_all else []), "exists in the client, missing in the simulator: errors here only")
    if sim_gap_global and not show_all:
        print(f"  ({len(sim_gap_global)} client global function(s) called by the addon are also missing in the simulator; --all lists them)")

    bad_cvars = [(n, w) for n, w in sorted(cvar_refs.items()) if cvars and n.lower() not in cvars]
    section("UNKNOWN CVAR", bad_cvars, "not in the client CVar list (addon-registered CVars are fine)")
    known = [(n, w) for n, w in sorted(cvar_refs.items()) if n.lower() in cvars]
    if known:
        print("  CVars used (client default): " + ", ".join(f"{n}={cvars[n.lower()].get('default', '?')}" for n, _ in known))
    bad_events = [(n, w) for n, w in sorted(event_refs.items()) if events and n not in events]
    section("UNKNOWN EVENT", bad_events, "not in the client event list: RegisterEvent would raise")
    if not (not_in_client or sim_only or sim_gap_ns or bad_cvars or bad_events):
        print("  nothing to report")


if __name__ == "__main__":
    main()
