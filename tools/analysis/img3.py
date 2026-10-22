"""Decrypt the DATA payload of an IMG3 file (and LZSS-decompress a kernelcache).

usage: img3.py IN OUT IV KEY
"""
import struct
import subprocess
import sys


def tags(buf):
    magic, full, _nopack, _sigarea, ident = struct.unpack_from("<4sIII4s", buf, 0)
    assert magic == b"3gmI", f"not IMG3: {magic!r}"
    off = 20
    while off < full:
        tmagic, total, dlen = struct.unpack_from("<4sII", buf, off)
        yield tmagic[::-1].decode(), buf[off + 12 : off + 12 + dlen]
        off += total


def aes_cbc_decrypt(data, iv, key):
    n = len(data) & ~0xF
    out = subprocess.run(
        ["openssl", "enc", "-d", "-aes-256-cbc", "-nopad", "-K", key, "-iv", iv],
        input=data[:n], capture_output=True, check=True,
    ).stdout
    return out + data[n:]


def lzss_decompress(src, out_len):
    # Apple's LZSS (Okumura variant, N=4096, F=18, THRESHOLD=2)
    N, F, T = 4096, 18, 2
    text = bytearray(b" " * (N + F - 1))
    r = N - F
    out = bytearray()
    i = 0
    flags = 0
    while i < len(src) and len(out) < out_len:
        flags >>= 1
        if not flags & 0x100:
            flags = src[i] | 0xFF00
            i += 1
            if i >= len(src):
                break
        if flags & 1:
            c = src[i]; i += 1
            out.append(c); text[r] = c; r = (r + 1) & (N - 1)
        else:
            if i + 1 >= len(src):
                break
            a, b = src[i], src[i + 1]; i += 2
            pos = a | ((b & 0xF0) << 4)
            ln = (b & 0x0F) + T
            for k in range(ln + 1):
                c = text[(pos + k) & (N - 1)]
                out.append(c); text[r] = c; r = (r + 1) & (N - 1)
    return bytes(out[:out_len])


def main():
    src, dst, iv, key = sys.argv[1:5]
    buf = open(src, "rb").read()
    found = dict(tags(buf))
    data = found["DATA"]
    plain = aes_cbc_decrypt(data, iv, key)
    if plain[:8] == b"complzss":
        _magic, _adler, out_len, in_len = struct.unpack_from(">8sIII", plain, 0)
        plain = lzss_decompress(plain[0x180 : 0x180 + in_len], out_len)
    open(dst, "wb").write(plain)
    print(f"{dst}: {len(plain)} bytes, tags={list(found)}")


if __name__ == "__main__":
    main()
