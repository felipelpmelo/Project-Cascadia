#!/usr/bin/env python3
"""Copy one file out of a remote IPSW, reading only the bytes it needs.

    ipsw-member.py URL MEMBER OUT

An IPSW is a ZIP, and Apple's servers answer HTTP range requests, so the
central directory and one member can be read without fetching the other
1.5 GB.  ./cascadia firmware uses it on boards other than p105 for
kernelcache.release.p105, which the GPU firmware comes from
(scripts/board.sh).  Standard library only: it runs on the host.
"""
import io
import os
import sys
import urllib.request
import zipfile


class RangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as r:
            self.size = int(r.headers["Content-Length"])
        self.pos = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def readinto(self, b):
        if self.pos >= self.size or len(b) == 0:
            return 0
        end = min(self.pos + len(b), self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        b[: len(data)] = data
        self.pos += len(data)
        return len(data)


def main():
    if len(sys.argv) != 4:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    url, member, out = sys.argv[1:]
    zf = zipfile.ZipFile(io.BufferedReader(RangeFile(url), buffer_size=1 << 20))
    tmp = out + ".part"
    with zf.open(member) as src, open(tmp, "wb") as dst:
        while chunk := src.read(1 << 20):
            dst.write(chunk)
    os.replace(tmp, out)
    print(f"{out}: {os.path.getsize(out)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
