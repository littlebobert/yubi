#!/usr/bin/env python3
"""Compute the next CFBundleVersion higher than App Store Connect and local floors."""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def _jwt(key_id: str, issuer_id: str, private_key: str) -> str:
    try:
        import jwt  # type: ignore
    except ImportError:
        import subprocess

        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet", "PyJWT", "cryptography"],
            stdout=subprocess.DEVNULL,
        )
        import jwt  # type: ignore

    now = int(time.time())
    token = jwt.encode(
        {
            "iss": issuer_id,
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    if isinstance(token, bytes):
        return token.decode()
    return token


def _api_get(url: str, token: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"App Store Connect API {error.code} for {url}: {body}") from error


def _parse_build_number(raw: str | None) -> int | None:
    if not raw:
        return None
    text = str(raw).strip()
    if not text:
        return None
    # Prefer leading integer ("8", "8.1" -> 8). ASC prefers pure integers for iOS builds.
    digits = ""
    for ch in text:
        if ch.isdigit():
            digits += ch
        elif digits:
            break
    if not digits:
        return None
    return int(digits)


def _latest_uploaded_build(token: str, bundle_id: str) -> int:
    apps = _api_get(
        "https://api.appstoreconnect.apple.com/v1/apps?"
        + urllib.parse.urlencode({"filter[bundleId]": bundle_id, "limit": "1"}),
        token,
    )
    data = apps.get("data") or []
    if not data:
        print(f"No App Store Connect app found for bundle id {bundle_id}; starting from floors only.", file=sys.stderr)
        return 0

    app_id = data[0]["id"]
    highest = 0

    # Pre-release / TestFlight + App Store builds share cfBundleVersion uniqueness per app.
    builds_url = (
        "https://api.appstoreconnect.apple.com/v1/builds?"
        + urllib.parse.urlencode(
            {
                "filter[app]": app_id,
                "sort": "-version",
                "limit": "50",
                "fields[builds]": "version,uploadedDate",
            }
        )
    )
    builds = _api_get(builds_url, token)
    for item in builds.get("data") or []:
        number = _parse_build_number((item.get("attributes") or {}).get("version"))
        if number is not None:
            highest = max(highest, number)

    # Also check App Store versions' build membership if present.
    versions_url = (
        f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions?"
        + urllib.parse.urlencode({"limit": "10", "fields[appStoreVersions]": "versionString"})
    )
    try:
        versions = _api_get(versions_url, token)
    except SystemExit as error:
        print(f"Warning: could not list appStoreVersions ({error})", file=sys.stderr)
        versions = {"data": []}

    for version in versions.get("data") or []:
        version_id = version["id"]
        rel = _api_get(
            f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{version_id}/build?"
            + urllib.parse.urlencode({"fields[builds]": "version"}),
            token,
        )
        item = rel.get("data")
        if not item:
            continue
        number = _parse_build_number((item.get("attributes") or {}).get("version"))
        if number is not None:
            highest = max(highest, number)

    return highest


def main() -> int:
    key_id = _require("APP_STORE_CONNECT_KEY_ID")
    issuer_id = _require("APP_STORE_CONNECT_ISSUER_ID")
    private_key = _require("APP_STORE_CONNECT_API_KEY")
    bundle_id = os.environ.get("BUNDLE_ID", "com.justin.yubi").strip()

    floors: list[int] = []
    for env_name in ("GITHUB_RUN_NUMBER", "PROJECT_BUILD_FLOOR", "MIN_BUILD_NUMBER"):
        parsed = _parse_build_number(os.environ.get(env_name))
        if parsed is not None:
            floors.append(parsed)

    token = _jwt(key_id, issuer_id, private_key)
    latest = _latest_uploaded_build(token, bundle_id)
    if latest > 0:
        floors.append(latest + 1)

    if not floors:
        floors.append(1)

    build_number = max(floors)
    marketing = os.environ.get("MARKETING_VERSION", "").strip()

    # Optional GitHub Actions outputs.
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with Path(output_path).open("a", encoding="utf-8") as handle:
            handle.write(f"build_number={build_number}\n")
            if marketing:
                handle.write(f"marketing={marketing}\n")

    print(f"latest_uploaded={latest}")
    print(f"build_number={build_number}")
    if marketing:
        print(f"marketing={marketing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
