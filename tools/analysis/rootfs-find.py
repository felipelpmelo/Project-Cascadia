"""Find files by name in an IPSW's encrypted root DMG, using Cascadia's reader.

usage: rootfs-find.py DMG_FILE KEYHEX REGEX [REGEX ...]

DMG_FILE is the root DMG already copied out of the IPSW (unzip -p).  Prints
the full path, size and (for small files) md5 of every file whose name
matches one of the regexes.
"""
import hashlib
import importlib.util
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location("rx", os.path.join(ROOT, "scripts", "rootfs-extract.py"))
rx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rx)

dmg, keyhex = sys.argv[1], sys.argv[2]
pats = [re.compile(p) for p in sys.argv[3:]]
key = bytes.fromhex(keyhex)

with open(dmg, "rb") as f:
    src = rx.Encrcdsa(f, key) if f.read(8) == b"encrcdsa" else rx.Plain(f)
    hfs = rx.Hfs(rx.Udif(src))
    folders = {2: ""}            # cnid -> path
    parent_of = {}               # folder cnid -> (parent cnid, name)
    files = []
    for node, o in hfs.leaves(hfs.catalog):
        klen = rx.u16(node, o)
        parent = rx.u32(node, o + 2)
        nlen = rx.u16(node, o + 6)
        name = node[o + 8:o + 8 + 2 * nlen].decode("utf-16-be")
        rec = node[o + 2 + klen:o + 2 + klen + 248]
        kind = struct.unpack_from(">h", rec, 0)[0]
        if kind == 1:
            parent_of[rx.u32(rec, 8)] = (parent, name)
        elif kind == 2 and any(p.search(name) for p in pats):
            files.append((parent, name, rec))

    def path(cnid):
        parts = []
        while cnid in parent_of:
            cnid, name = parent_of[cnid]
            parts.append(name)
        return "/" + "/".join(reversed(parts))

    for parent, name, rec in sorted(files, key=lambda x: (path(x[0]), x[1])):
        size = rx.u64(rec, 88)
        md5 = ""
        if size < 4 << 20:
            md5 = hashlib.md5(hfs.read_file(rec)).hexdigest()
        print(f"{size:>10}  {md5:32}  {path(parent).rstrip('/')}/{name}")
