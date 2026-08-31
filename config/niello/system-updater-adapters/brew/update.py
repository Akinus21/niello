#!/usr/bin/env python3
"""
Homebrew adapter update script for the tordex/system-updater Noctalia
plugin. Invoked as either:
  update.py <package_name>   — upgrade one formula/cask
  update.py --all            — upgrade everything outdated
"""
import os
import shutil
import subprocess
import sys


def find_brew():
    candidates = [
        os.path.expanduser("~/.homebrew/bin/brew"),
        "/home/linuxbrew/.linuxbrew/bin/brew",
        shutil.which("brew"),
    ]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def main():
    if len(sys.argv) != 2:
        print("usage: update.py <package_name> | update.py --all", file=sys.stderr)
        sys.exit(1)

    brew = find_brew()
    if not brew:
        print("brew not found", file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--all":
        cmd = [brew, "upgrade"]
    else:
        cmd = [brew, "upgrade", sys.argv[1]]

    result = subprocess.run(cmd)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
