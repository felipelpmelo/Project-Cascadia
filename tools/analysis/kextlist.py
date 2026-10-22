"""List prelinked kexts (bundle id, load address, size) in a 32-bit kernelcache.
usage: kextlist.py KERNELCACHE"""
import re, struct, sys
kc = open(sys.argv[1], "rb").read()
ncmds = struct.unpack_from("<I", kc, 16)[0]
off = 28
info = None
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", kc, off)
    if cmd == 1:  # LC_SEGMENT
        name = kc[off + 8:off + 24].rstrip(b"\0").decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<IIII", kc, off + 24)
        if name == "__PRELINK_INFO":
            info = kc[fileoff:fileoff + filesize]
    off += size
xml = info.decode("latin-1")
for d in re.finditer(r"<dict>(.*?)</dict>", xml, re.S):
    body = d.group(1)
    bid = re.search(r"<key>CFBundleIdentifier</key><string>([^<]+)", body)
    addr = re.search(r"<key>_PrelinkExecutableLoadAddr</key><integer[^>]*>(0x[0-9a-f]+|\d+)", body)
    size = re.search(r"<key>_PrelinkExecutableSize</key><integer[^>]*>(0x[0-9a-f]+|\d+)", body)
    if bid and addr:
        print(f"{int(addr.group(1), 0):#010x} {int(size.group(1), 0) if size else 0:#08x} {bid.group(1)}")
