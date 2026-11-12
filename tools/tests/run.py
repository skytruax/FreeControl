#!/usr/bin/env python3
"""Runs FreeControl's Lua tests without the game.

    pip install lupa          # Lua 5.1 embedded in Python
    python3 tools/tests/run.py [name-filter] [--globals]

Every test runs in its own Lua 5.1 state: the mock client (wowmock.lua) is loaded, then the
addon's files in .toc order, then one scenario from tests.lua. Exit status is non-zero if any fail.
"""
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def new_state():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ReadFile = read
    load = lua.eval("function(src, name) return assert(loadstring(src, name))() end")
    for name in ("wowmock.lua", "tests.lua"):
        load(read(os.path.join("tools", "tests", name)), "@tools/tests/" + name)
    return lua


def main():
    args = [a for a in sys.argv[1:] if a != "--globals"]
    wanted = args[0] if args else ""
    reads, writes = set(), set()
    names = [t.name for t in new_state().globals().TESTS.values()]
    failed = 0
    ran = 0
    for index, name in enumerate(names, start=1):
        if wanted not in name:
            continue
        ran += 1
        lua = new_state()
        run = lua.eval("""function(index)
            local ok, err = xpcall(TESTS[index].fn, function(e) return debug.traceback(tostring(e), 2) end)
            return ok, err
        end""")
        ok, err = run(index)
        reads.update(lua.globals().GLOBAL_READS.keys())
        writes.update(lua.globals().GLOBAL_WRITES.keys())
        if ok:
            print("ok    " + name)
        else:
            failed += 1
            print("FAIL  " + name)
            print("      " + str(err).replace("\n", "\n      "))
    print("\n%d run, %d failed" % (ran, failed))
    if "--globals" in sys.argv:
        print("\nGlobals the addon read while the tests ran:\n  " + " ".join(sorted(reads)))
        print("\nGlobals it wrote:\n  " + " ".join(sorted(writes)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
