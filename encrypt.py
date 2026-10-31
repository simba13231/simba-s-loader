#!/usr/bin/env python3
"""
Simba Loader encryptor
======================
Encrypts an AutoHotkey script into a passphrase-protected blob.

Scheme:
  - AES-256-CBC, PKCS7 padding, random 16-byte salt + random 16-byte IV per build
  - Key = PBKDF2-HMAC-SHA256(passphrase, salt, 200000 iterations, 32 bytes)
  - Blob layout (base64-encoded in the .enc file): SIMBA1 | salt(16) | iv(16) | ciphertext
  - passphrase.hash stores SHA-256(PBKDF2(passphrase, "simba-verify-salt-v1")) —
    a verifier only. It can NOT decrypt anything; it just lets the loader say
    "wrong passphrase" instantly.

Usage:
    pip install pycryptodome        (once)
    python encrypt.py <script.ahk> [output.enc]

It prompts for the passphrase (hidden input).
The repo never contains the passphrase or the key. Keep the passphrase
in your head / password manager and share it only in private.
"""
import base64
import getpass
import hashlib
import os
import secrets
import sys
from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

MAGIC = b"SIMBA1"
ITERATIONS = 200000          # keep in sync with loader.ahk
VERIFY_SALT = b"simba-verify-salt-v1"   # keep in sync with loader.ahk


def derive(passphrase: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac(
        "sha256", passphrase.encode("utf-8"), salt, ITERATIONS, dklen=32
    )


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: python encrypt.py <script.ahk> [output.enc]")
        sys.exit(1)

    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".enc")
    plaintext = src.read_bytes()

    pw = os.environ.get("SIMBA_PASS") or ""
    if pw:
        print("using passphrase from SIMBA_PASS env var")
    else:
        pw = getpass.getpass("Passphrase: ")
        pw2 = getpass.getpass("Confirm:     ")
        if pw != pw2:
            sys.exit("ERROR: passphrases do not match")
    if not pw:
        sys.exit("ERROR: empty passphrase")

    salt = secrets.token_bytes(16)
    iv = secrets.token_bytes(16)
    key = derive(pw, salt)
    ct = AES.new(key, AES.MODE_CBC, iv).encrypt(pad(plaintext, 16))

    blob = MAGIC + salt + iv + ct
    out.write_bytes(blob)

    verifier = hashlib.sha256(derive(pw, VERIFY_SALT)).hexdigest()
    Path("passphrase.hash").write_text(verifier + "\n", encoding="ascii")

    print(f"[ok] wrote {out} ({len(blob)} bytes, {len(ct)} ct bytes)")
    print(f"[ok] wrote passphrase.hash ({verifier[:16]}...)")


if __name__ == "__main__":
    main()
