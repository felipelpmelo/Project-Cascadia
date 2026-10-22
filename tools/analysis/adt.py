"""Parse an Apple Device Tree (ADT) and print or diff it.

usage: adt.py dump FILE
       adt.py diff FILE_A FILE_B
"""
import struct
import sys


def parse(buf, off=0, path=""):
    nprops, nchildren = struct.unpack_from("<II", buf, off)
    off += 8
    props = {}
    for _ in range(nprops):
        name = buf[off : off + 32].split(b"\0")[0].decode("latin-1")
        (ln,) = struct.unpack_from("<I", buf, off + 32)
        ln &= 0x7FFFFFFF
        props[name] = buf[off + 36 : off + 36 + ln]
        off += 36 + ((ln + 3) & ~3)
    name = props.get("name", b"?").split(b"\0")[0].decode("latin-1")
    me = f"{path}/{name}" if path else name
    nodes = {me: props}
    for _ in range(nchildren):
        child, off = parse(buf, off, me)
        for k in child:
            key = k
            n = 1
            while key in nodes:
                n += 1
                key = f"{k}#{n}"
            nodes[key] = child[k]
    return nodes, off


def fmt(v):
    printable = all(32 <= c < 127 or c == 0 for c in v) and v.rstrip(b"\0") and b"\0" not in v.rstrip(b"\0")
    if printable:
        return repr(v.rstrip(b"\0").decode())
    if len(v) <= 64:
        return v.hex()
    return v[:64].hex() + f"...({len(v)} bytes)"


def load(p):
    return parse(open(p, "rb").read())[0]


def main():
    cmd = sys.argv[1]
    if cmd == "dump":
        for path, props in load(sys.argv[2]).items():
            print(path)
            for k, v in props.items():
                print(f"    {k} = {fmt(v)}")
    elif cmd == "diff":
        a, b = load(sys.argv[2]), load(sys.argv[3])
        for path in sorted(set(a) | set(b)):
            if path not in b:
                print(f"- NODE {path}")
                continue
            if path not in a:
                print(f"+ NODE {path}")
                for k, v in b[path].items():
                    print(f"+     {k} = {fmt(v)}")
                continue
            pa, pb = a[path], b[path]
            for k in sorted(set(pa) | set(pb)):
                if pa.get(k) != pb.get(k):
                    print(f"~ {path} :: {k}")
                    print(f"      A: {fmt(pa[k]) if k in pa else '(absent)'}")
                    print(f"      B: {fmt(pb[k]) if k in pb else '(absent)'}")


if __name__ == "__main__":
    main()
