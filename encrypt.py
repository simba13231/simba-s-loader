#!/usr/bin/env python3
"""
Simba Loader encryptor (original blob format — matches loader DecryptBlob)

Blob format:  base64( IV(16) || AES-256-CBC( PKCS7(script) ) )
AES key:      SHA-256(master_key_hex_string)   32 bytes
              ^ the master key is NOT stored in this repo, ever.
                Keep it inside the compiled loader + this tool locally.

Usage:
    pip install pycryptodome                      (once)
    python encrypt.py <script.ahk> [output.enc]   encrypt a script
    python encrypt.py keyhash <userkey>           print a keys.txt line

Master key comes from the MASTER_KEY_HEX env var, or a hidden prompt.
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


def get_master() -> str:
    mk = os.environ.get("MASTER_KEY_HEX", "").strip()
    if mk:
        print("using master key from MASTER_KEY_HEX env var")
        return mk
    mk = getpass.getpass("Master key (hex): ").strip()
    if not mk:
        sys.exit("ERROR: empty master key")
    return mk


def main() -> None:
    # keyhash mode: print the SHA-256 line to paste into keys.txt
    if len(sys.argv) >= 2 and sys.argv[1] == "keyhash":
        user_key = sys.argv[2] if len(sys.argv) > 2 else getpass.getpass("User key to hash: ")
        if not user_key:
            sys.exit("ERROR: empty key")
        print(hashlib.sha256(user_key.encode("utf-8")).hexdigest())
        return

    if len(sys.argv) < 2:
        print("usage: python encrypt.py <script.ahk> [output.enc]")
        print("       python encrypt.py keyhash <userkey>")
        sys.exit(1)

    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".enc")

    master = get_master()
    key = hashlib.sha256(master.encode("utf-8")).digest()
    iv = secrets.token_bytes(16)
    ct = AES.new(key, AES.MODE_CBC, iv).encrypt(pad(src.read_bytes(), 16))

    out.write_bytes(base64.b64encode(iv + ct))
    print(f"[ok] wrote {out} ({out.stat().st_size} bytes b64, {len(ct)} ct bytes)")


if __name__ == "__main__":
    main()
