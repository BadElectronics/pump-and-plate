#!/usr/bin/env python3
"""Prints the Apple Team ID that owns an app's bundle ID.

Used by the cloud build to sign the iPhone app without keeping the Team ID in
the code. Reads the App Store Connect API key from the environment:

  APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_PATH

  python3 scripts/apple-team-id.py com.pumpandplate.app
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

import jwt  # PyJWT, with the cryptography package for ES256


def token():
    key = open(os.environ["APP_STORE_CONNECT_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 600,
         "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )


def main():
    bundle_id = sys.argv[1]
    query = urllib.parse.urlencode({"filter[identifier]": bundle_id, "fields[bundleIds]": "identifier,seedId"})
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v1/bundleIds?{query}",
        headers={"Authorization": f"Bearer {token()}"},
    )
    try:
        data = json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect said {e.code}: {e.read().decode()[:500]}")
    for item in data.get("data", []):
        attrs = item["attributes"]
        if attrs.get("identifier") == bundle_id and attrs.get("seedId"):
            print(attrs["seedId"])
            return
    sys.exit(f"No App ID {bundle_id} found. Register it at developer.apple.com → Identifiers.")


if __name__ == "__main__":
    main()
