"""Diff two ADTs with phandle references resolved to node paths.

usage: adt-semdiff.py DEVICETREE_A DEVICETREE_B

Inputs are decrypted DeviceTree payloads (img3.py).  Phandles differ between
boards even where the hardware is the same; this prints only what differs
once every function-*, interrupt-parent and iommu-parent reference is
replaced by the node path it points to.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from adt import load, fmt

def resolver(nodes):
    m = {}
    for path, p in nodes.items():
        if "AAPL,phandle" in p:
            m[struct.unpack("<I", p["AAPL,phandle"][:4])[0]] = path.replace("device-tree/", "")
    return m

def norm(key, v, ph):
    if key == "AAPL,phandle":
        return None
    if key.startswith("function-") and len(v) >= 8:
        h = struct.unpack_from("<I", v, 0)[0]
        cc = v[4:8][::-1].decode("latin-1")
        args = [struct.unpack_from("<I", v, i)[0] for i in range(8, len(v) - len(v) % 4, 4)]
        return f"{ph.get(h, hex(h))} {cc} {' '.join(hex(a) for a in args)}"
    if key in ("interrupt-parent", "iommu-parent") and len(v) == 4:
        h = struct.unpack("<I", v)[0]
        return ph.get(h, hex(h))
    return fmt(v)

a, b = load(sys.argv[1]), load(sys.argv[2])
pa, pb = resolver(a), resolver(b)
for path in sorted(set(a) | set(b)):
    short = path.replace("device-tree/", "")
    if path not in b:
        print(f"- NODE {short}"); continue
    if path not in a:
        print(f"+ NODE {short}")
        for k, v in b[path].items():
            n = norm(k, v, pb)
            if n is not None: print(f"      {k} = {n}")
        continue
    for k in sorted(set(a[path]) | set(b[path])):
        x = norm(k, a[path][k], pa) if k in a[path] else "(absent)"
        y = norm(k, b[path][k], pb) if k in b[path] else "(absent)"
        if x != y:
            print(f"~ {short} :: {k}\n      p105: {x}\n      p106: {y}")
