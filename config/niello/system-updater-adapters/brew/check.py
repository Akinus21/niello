#!/usr/bin/env python3
"""
Homebrew adapter check script for the tordex/system-updater Noctalia
plugin. Outputs the plugin's expected check_command JSON shape:
https://noctalia.dev/plugins/community/system-updater

Resolves brew's path directly rather than relying on it being present
in the adapter subprocess's PATH, since niello-init installs it under
~/.homebrew or /home/linuxbrew/.linuxbrew, not always guaranteed to be
inherited by whatever environment spawns the plugin's check_command.
"""
import json
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


def fail(message):
    print(json.dumps({"info": message, "actions": [], "updates": []}))
    sys.exit(0)


def main():
    brew = find_brew()
    if not brew:
        fail("brew not found — checked ~/.homebrew, /home/linuxbrew/.linuxbrew, and PATH")

    # Refresh formula/cask metadata before checking. A failure here
    # (e.g. transient network issue) shouldn't block showing whatever
    # outdated list brew can still compute from its last-known state.
    try:
        subprocess.run([brew, "update"], capture_output=True, timeout=120)
    except Exception:
        pass

    try:
        result = subprocess.run(
            [brew, "outdated", "--json=v2"],
            capture_output=True, text=True, timeout=60, check=True,
        )
    except subprocess.CalledProcessError as e:
        fail(f"brew outdated failed: {e.stderr.strip() or e}")
    except Exception as e:
        fail(f"brew outdated failed: {e}")

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        fail("brew outdated returned invalid JSON")

    updates = []

    for pkg in data.get("formulae", []):
        installed = pkg.get("installed_versions") or []
        updates.append({
            "id": pkg.get("name", ""),
            "name": pkg.get("name", ""),
            "description": "Homebrew formula",
            "from_version": installed[-1] if installed else "",
            "to_version": pkg.get("current_version", ""),
        })

    for pkg in data.get("casks", []):
        installed = pkg.get("installed_versions")
        if isinstance(installed, list):
            from_version = installed[-1] if installed else ""
        else:
            from_version = installed or ""
        updates.append({
            "id": pkg.get("name", ""),
            "name": pkg.get("name", ""),
            "description": "Homebrew cask",
            "from_version": from_version,
            "to_version": pkg.get("current_version", ""),
        })

    print(json.dumps({"info": "", "actions": [], "updates": updates}))


if __name__ == "__main__":
    main()
