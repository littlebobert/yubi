#!/usr/bin/env python3
"""Compute the next CFBundleVersion higher than App Store Connect and local floors.

Uses only the Python stdlib + openssl (already on GitHub macOS runners).
No pip / PyJWT install required.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
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


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _jwt(key_id: str, issuer_id: str, private_key_pem: str) -> str:
    """Create an App Store Connect API JWT (ES256) via openssl."""
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }

    signing_input = (
        f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    ).encode("ascii")

    with tempfile.TemporaryDirectory() as tmp:
        key_path = Path(tmp) / "AuthKey.p8"
        sig_path = Path(tmp) / "sig.der"
        key_path.write_text(private_key_pem if private_key_pem.endswith("\n") else private_key_pem + "\n")

        # ECDSA-SHA256 DER signature over the JWT signing input.
        result = subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-sign",
                str(key_path),
                "-out",
                str(sig_path),
            ],
            input=signing_input,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            err = result.stderr.decode("utf-8", errors="replace")
            raise SystemExit(f"openssl failed to sign App Store Connect JWT: {err}")

        der_sig = sig_path.read_bytes()

    jose_sig = _der_ecdsa_to_jose(der_sig)
    return f"{signing_input.decode('ascii')}.{_b64url(jose_sig)}"


def _der_ecdsa_to_jose(der_sig: bytes) -> bytes:
    """Convert OpenSSL DER ECDSA signature to raw R||S (JOSE ES256, 64 bytes)."""
    # DER: SEQUENCE { INTEGER r, INTEGER s }
    if len(der_sig) < 8 or der_sig[0] != 0x30:
        raise SystemExit("Unexpected ECDSA DER signature format")

    idx = 2 if der_sig[1] < 0x80 else 3

    if der_sig[idx] != 0x02:
        raise SystemExit("Unexpected ECDSA DER signature (missing r)")
    r_len = der_sig[idx + 1]
    r = der_sig[idx + 2 : idx + 2 + r_len]
    idx = idx + 2 + r_len

    if der_sig[idx] != 0x02:
        raise SystemExit("Unexpected ECDSA DER signature (missing s)")
    s_len = der_sig[idx + 1]
    s = der_sig[idx + 2 : idx + 2 + s_len]

    def fixed(value: bytes) -> bytes:
        value = value.lstrip(b"\x00") or b"\x00"
        if len(value) > 32:
            raise SystemExit("ECDSA coordinate longer than 32 bytes")
        return value.rjust(32, b"\x00")

    return fixed(r) + fixed(s)


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
        print(
            f"No App Store Connect app found for bundle id {bundle_id}; starting from floors only.",
            file=sys.stderr,
        )
        return 0

    app_id = data[0]["id"]
    highest = 0

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
