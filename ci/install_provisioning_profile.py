#!/usr/bin/env python3
"""Install a .mobileprovision into ~/Library/MobileDevice/Provisioning Profiles."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <profile.mobileprovision>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    data = path.read_bytes()
    start = data.find(b"<?xml")
    end = data.find(b"</plist>")
    if start < 0 or end < 0:
        print(f"Could not parse provisioning profile: {path}", file=sys.stderr)
        return 1

    plist = plistlib.loads(data[start : end + len(b"</plist>")])
    name = plist["Name"]
    uuid = plist["UUID"]
    app_id = (plist.get("Entitlements") or {}).get("application-identifier", "?")

    profiles_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    profiles_dir.mkdir(parents=True, exist_ok=True)
    dest = profiles_dir / f"{uuid}.mobileprovision"
    dest.write_bytes(data)

    print(f"Installed profile: name={name!r} uuid={uuid} app_id={app_id} -> {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
