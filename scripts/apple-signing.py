#!/usr/bin/env python3
"""App Store signing for the cloud build.

The build signs with a stored Apple Distribution certificate when the repo
has one in its secrets (IOS_DIST_P12_BASE64 and IOS_DIST_P12_PASSWORD),
which is what App Review needs: it checks a build's signature again at
submission, so a certificate revoked after the upload fails with
ITMS-90035. Without a stored certificate the build makes a throwaway one
and revokes it afterwards, which is fine for TestFlight only.

Needs the App Store Connect API key in the environment:
  APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_PATH

  apple-signing.py make-certificate OUT_DIR P12_PASSWORD
      Makes a new Apple Distribution certificate and writes OUT_DIR/dist.p12
      (protected by P12_PASSWORD) and OUT_DIR/dist.p12.base64.txt, the text
      to put in the IOS_DIST_P12_BASE64 secret.
  apple-signing.py setup BUNDLE_ID OUT_DIR P12_PASSWORD [STORED_P12]
      Makes a provisioning profile for this build, using the stored
      certificate when STORED_P12 is given (P12_PASSWORD must open it) or a
      fresh throwaway one otherwise. Writes OUT_DIR/dist.p12 and
      OUT_DIR/profile.mobileprovision and prints key=value lines:
      team, cert_id, cert_stored, profile_id, profile_name, profile_uuid.
  apple-signing.py cleanup CERT_ID PROFILE_ID [keep-certificate]
      Deletes the profile, and the certificate unless told to keep it.
"""
import base64
import datetime
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = open(os.environ["APP_STORE_CONNECT_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect said {e.code} to {method} {path}: {e.read().decode()[:800]}")


def bundle(bundle_id):
    q = urllib.parse.urlencode({"filter[identifier]": bundle_id, "fields[bundleIds]": "identifier,seedId"})
    for item in call("GET", f"/bundleIds?{q}").get("data", []):
        if item["attributes"].get("identifier") == bundle_id:
            return item["id"], item["attributes"]["seedId"]
    sys.exit(f"No App ID {bundle_id}. Register it at developer.apple.com → Identifiers.")


def expires(certificate):
    """When a certificate expires, as an aware UTC time (works on older cryptography too)."""
    utc = getattr(certificate, "not_valid_after_utc", None)
    return utc or certificate.not_valid_after.replace(tzinfo=datetime.timezone.utc)


def p12_encryption(password):
    # The older p12 encryption, which macOS's keychain tool can read.
    return (serialization.PrivateFormat.PKCS12.encryption_builder()
            .kdf_rounds(2048)
            .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
            .hmac_hash(hashes.SHA1())
            .build(password.encode()))


def new_certificate(common_name):
    """A new key and Apple Distribution certificate. Returns (key, cert, cert_id)."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)]))
           .sign(key, hashes.SHA256()))
    cert = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION",
        "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode(),
    }}})["data"]
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    return key, x509.load_der_x509_certificate(der), cert["id"]


def make_certificate(out_dir, password):
    key, certificate, cert_id = new_certificate("Pump and Plate cloud build")
    os.makedirs(out_dir, exist_ok=True)
    p12 = pkcs12.serialize_key_and_certificates(b"Pump and Plate", key, certificate, None, p12_encryption(password))
    with open(os.path.join(out_dir, "dist.p12"), "wb") as f:
        f.write(p12)
    with open(os.path.join(out_dir, "dist.p12.base64.txt"), "w") as f:
        f.write(base64.b64encode(p12).decode())
    print(f"Made certificate {cert_id}, valid until {expires(certificate):%Y-%m-%d}.")


def stored_certificate_id(certificate):
    """The App Store Connect id of a certificate we already hold."""
    q = urllib.parse.urlencode({"filter[certificateType]": "DISTRIBUTION", "limit": 200})
    for item in call("GET", f"/certificates?{q}").get("data", []):
        der = base64.b64decode(item["attributes"]["certificateContent"])
        if x509.load_der_x509_certificate(der).serial_number == certificate.serial_number:
            return item["id"]
    sys.exit("The stored certificate isn't in App Store Connect any more (revoked or expired). "
             "Run the Build workflow with 'Make a new signing certificate' and update the secrets.")


def setup(bundle_id, out_dir, p12_password, stored_p12=None):
    bundle_res, team = bundle(bundle_id)
    os.makedirs(out_dir, exist_ok=True)

    if stored_p12:
        with open(stored_p12, "rb") as f:
            _key, certificate, _extra = pkcs12.load_key_and_certificates(f.read(), p12_password.encode())
        if expires(certificate) < datetime.datetime.now(datetime.timezone.utc):
            sys.exit("The stored certificate has expired. Make a new one and update the secrets.")
        cert_id = stored_certificate_id(certificate)
        shutil.copyfile(stored_p12, os.path.join(out_dir, "dist.p12"))
        stored = True
    else:
        key, certificate, cert_id = new_certificate("Pump and Plate cloud build")
        with open(os.path.join(out_dir, "dist.p12"), "wb") as f:
            f.write(pkcs12.serialize_key_and_certificates(b"Pump and Plate", key, certificate, None,
                                                          p12_encryption(p12_password)))
        stored = False

    name = f"Pump and Plate cloud build {time.strftime('%Y%m%d-%H%M%S')}"
    profile = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_res}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        },
    }})["data"]
    with open(os.path.join(out_dir, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(profile["attributes"]["profileContent"]))

    print(f"team={team}")
    print(f"cert_id={cert_id}")
    print(f"cert_stored={'true' if stored else 'false'}")
    print(f"profile_id={profile['id']}")
    print(f"profile_name={name}")
    print(f"profile_uuid={profile['attributes']['uuid']}")


def cleanup(cert_id, profile_id, keep_certificate):
    paths = [f"/profiles/{profile_id}"]
    if not keep_certificate:
        paths.append(f"/certificates/{cert_id}")
    for path in paths:
        req = urllib.request.Request(API + path, method="DELETE", headers={"Authorization": f"Bearer {token()}"})
        try:
            urllib.request.urlopen(req, timeout=60)
            print(f"Removed {path}")
        except urllib.error.HTTPError as e:
            print(f"Couldn't remove {path}: {e.code}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == "make-certificate":
        make_certificate(a[1], a[2])
    elif len(a) in (4, 5) and a[0] == "setup":
        setup(a[1], a[2], a[3], a[4] if len(a) == 5 else None)
    elif len(a) in (3, 4) and a[0] == "cleanup":
        cleanup(a[1], a[2], len(a) == 4 and a[3] == "keep-certificate")
    else:
        sys.exit(__doc__)
