"""Extract selected members of a remote ZIP using HTTP range requests.

usage: ipsw-remote.py URL OUTDIR [--list] [PATTERN ...]
"""
import fnmatch
import io
import os
import sys
import urllib.request
import zipfile


class RangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r:
            self.size = int(r.headers["Content-Length"])
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        if whence == 0:
            self.pos = off
        elif whence == 1:
            self.pos += off
        else:
            self.pos = self.size + off
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def main():
    url, out = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    zf = zipfile.ZipFile(io.BufferedReader(RangeFile(url), buffer_size=1 << 20))
    if args and args[0] == "--list":
        for i in zf.infolist():
            print(f"{i.file_size:>12}  {i.filename}")
        return
    os.makedirs(out, exist_ok=True)
    for i in zf.infolist():
        if not i.is_dir() and any(fnmatch.fnmatch(i.filename, p) for p in args):
            dest = os.path.join(out, os.path.basename(i.filename))
            with zf.open(i) as src, open(dest, "wb") as dst:
                while chunk := src.read(1 << 20):
                    dst.write(chunk)
            print(f"{i.file_size:>12}  {i.filename}")


if __name__ == "__main__":
    main()
