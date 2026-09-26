#!/usr/bin/env python3
"""Every promise the tests make, broken on a copy, has to be noticed.

A test that cannot fail is not a test. Each line of tests/plants.tsv names a
file, a piece of it, and what to put there instead; each one breaks a
behaviour the tests assert. This runs the test command on an untouched copy,
which has to pass, then on one copy per plant, each of which has to fail. A
plant whose text is no longer in the file fails the run too, so the tests
cannot fall behind the code unnoticed.

    ./tests/plant-violations.py -- <the test command, run inside each copy>

A literal {dir} in the command is replaced by the copy's path.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(cmd, d):
    argv = [a.replace("{dir}", d) for a in cmd]
    return subprocess.run(argv, cwd=d, capture_output=True, text=True, stdin=subprocess.DEVNULL)


def copy():
    work = tempfile.mkdtemp(prefix="plant-")
    shutil.copytree(ROOT, work, dirs_exist_ok=True, symlinks=True, ignore=shutil.ignore_patterns(".git"))
    return work


def main():
    if "--" not in sys.argv or sys.argv.index("--") == len(sys.argv) - 1:
        sys.exit(__doc__)
    cmd = sys.argv[sys.argv.index("--") + 1:]
    plants = []
    with open(os.path.join(ROOT, "tests", "plants.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            plants.append([json.loads(x) for x in line.rstrip("\n").split("\t")])
    if not plants:
        sys.exit("tests/plants.tsv has no plants: a test nothing tries to break proves nothing")

    work = copy()
    r = run(cmd, work)
    shutil.rmtree(work, ignore_errors=True)
    if r.returncode != 0:
        print(r.stdout[-3000:] + r.stderr[-3000:])
        sys.exit("the untouched code does not pass its own tests")
    print("  ok      the untouched code passes")

    missed = stale = 0
    for fname, old, new, what in plants:
        work = copy()
        path = os.path.join(work, fname)
        text = open(path, encoding="utf-8").read()
        if old not in text:
            print("  STALE   %s: the text this plant breaks is no longer in %s" % (what, fname))
            stale += 1
        else:
            open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
            if run(cmd, work).returncode == 0:
                print("  MISSED  %s" % what)
                missed += 1
            else:
                print("  caught  %s" % what)
        shutil.rmtree(work, ignore_errors=True)
    print("%d plants: %d caught, %d missed, %d stale" % (len(plants), len(plants) - missed - stale, missed, stale))
    sys.exit(1 if (missed or stale) else 0)


if __name__ == "__main__":
    main()
