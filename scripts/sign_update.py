#!/usr/bin/env python3
"""Signs release files for GitGaze's updaters with the existing Sparkle Ed25519 key.

One key protects every update path:
- `pubkey` prints the Tauri updater public key (minisign format) derived from SUPublicEDKey.
- `sign FILE VERSION` prints the base64 minisign signature Tauri's updater verifies.
- `sparkle FILE` prints the raw Ed25519 signature Sparkle verifies (sparkle:edSignature).
- `verify FILE SIGNATURE` checks a raw signature against the public key (needs no private key).

The private key is read from $SPARKLE_PRIVATE_KEY (Sparkle's exported base64 key: a 32-byte seed,
or a 64/96-byte legacy key). It is never printed or written to disk.
"""
import base64
import hashlib
import os
import sys
import time

SPARKLE_PUBLIC_KEY = "F21vDAB46KghInZ5pS5mbFY5xVheYg/T6nL4iGxTy+k="

# Ed25519 (RFC 8032) in pure Python, so CI needs no extra packages.
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
G_Y = 4 * pow(5, P - 2, P) % P


def _recover_x(y, sign):
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * pow(2, (P - 1) // 4, P) % P
    if x & 1 != sign:
        x = P - x
    return x


G = (_recover_x(G_Y, 0), G_Y, 1, _recover_x(G_Y, 0) * G_Y % P)


def _add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    A = (y1 - x1) * (y2 - x2) % P
    B = (y1 + x1) * (y2 + x2) % P
    C = 2 * t1 * t2 * D % P
    Dd = 2 * z1 * z2 % P
    E, F, Gg, H = B - A, Dd - C, Dd + C, B + A
    return (E * F % P, Gg * H % P, F * Gg % P, E * H % P)


def _mul(s, point):
    result = (0, 1, 1, 0)
    while s:
        if s & 1:
            result = _add(result, point)
        point = _add(point, point)
        s >>= 1
    return result


def _encode(point):
    x, y, z, _ = point
    zi = pow(z, P - 2, P)
    x, y = x * zi % P, y * zi % P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _secret():
    raw = base64.b64decode(os.environ["SPARKLE_PRIVATE_KEY"].strip())
    if len(raw) in (32, 64) and not (len(raw) == 64 and raw[32:] != _public_from_seed(raw[:32])):
        digest = hashlib.sha512(raw[:32]).digest()  # Seed (optionally followed by its public key).
        scalar = int.from_bytes(digest[:32], "little") & ((1 << 254) - 8) | (1 << 254)
        prefix = digest[32:]
    elif len(raw) in (64, 96):
        # Sparkle's legacy export: an expanded 64-byte secret (scalar ‖ prefix), then the public key.
        scalar, prefix = int.from_bytes(raw[:32], "little"), raw[32:64]
    else:
        sys.exit("Unrecognised SPARKLE_PRIVATE_KEY format")
    public = _encode(_mul(scalar, G))
    if base64.b64encode(public).decode() != SPARKLE_PUBLIC_KEY:
        sys.exit("SPARKLE_PRIVATE_KEY does not match the app's public key")
    return scalar, prefix, public


def _public_from_seed(seed):
    digest = hashlib.sha512(seed).digest()
    return _encode(_mul(int.from_bytes(digest[:32], "little") & ((1 << 254) - 8) | (1 << 254), G))


def ed25519_sign(message):
    scalar, prefix, public = _secret()
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % L
    big_r = _encode(_mul(r, G))
    k = int.from_bytes(hashlib.sha512(big_r + public + message).digest(), "little") % L
    return big_r + int.to_bytes((r + k * scalar) % L, 32, "little")


def ed25519_verify(message, signature, public=None):
    """Independent check of a signature against the app's public key (RFC 8032 verification)."""
    public = public or base64.b64decode(SPARKLE_PUBLIC_KEY)
    y = int.from_bytes(public, "little") & ((1 << 255) - 1)
    x = _recover_x(y, public[31] >> 7)
    point_a = (x, y, 1, x * y % P)
    r_bytes, s = signature[:32], int.from_bytes(signature[32:], "little")
    if s >= L:
        return False
    k = int.from_bytes(hashlib.sha512(r_bytes + public + message).digest(), "little") % L
    return _encode(_mul(s, G)) == _encode(_add(_decode(r_bytes), _mul(k, point_a)))


def _decode(data):
    y = int.from_bytes(data, "little") & ((1 << 255) - 1)
    x = _recover_x(y, data[31] >> 7)
    return (x, y, 1, x * y % P)


def _key_id():
    return hashlib.sha256(base64.b64decode(SPARKLE_PUBLIC_KEY)).digest()[:8]


def minisign_public_key():
    key = base64.b64encode(b"Ed" + _key_id() + base64.b64decode(SPARKLE_PUBLIC_KEY)).decode()
    text = f"untrusted comment: GitGaze update key {_key_id().hex().upper()}\n{key}\n"
    return base64.b64encode(text.encode()).decode()


def minisign_signature(path, version):
    data = open(path, "rb").read()
    signature = ed25519_sign(hashlib.blake2b(data, digest_size=64).digest())
    trusted = f"timestamp:{int(time.time())}\tfile:{os.path.basename(path)}\tversion:{version}"
    global_signature = ed25519_sign(signature + trusted.encode())
    text = (
        "untrusted comment: signature from GitGaze release key\n"
        + base64.b64encode(b"ED" + _key_id() + signature).decode()
        + f"\ntrusted comment: {trusted}\n"
        + base64.b64encode(global_signature).decode()
        + "\n"
    )
    return base64.b64encode(text.encode()).decode()


if __name__ == "__main__":
    if sys.argv[1:] == ["pubkey"]:
        print(minisign_public_key())
    elif len(sys.argv) == 4 and sys.argv[1] == "sign":
        print(minisign_signature(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) == 4 and sys.argv[1] == "verify":
        ok = ed25519_verify(open(sys.argv[2], "rb").read(), base64.b64decode(sys.argv[3]))
        sys.exit(0 if ok else "Signature does not match the app's public key")
    elif len(sys.argv) == 3 and sys.argv[1] == "sparkle":
        print(base64.b64encode(ed25519_sign(open(sys.argv[2], "rb").read())).decode())
    else:
        sys.exit("Usage: sign_update.py pubkey | sign FILE VERSION | sparkle FILE | verify FILE SIGNATURE")
