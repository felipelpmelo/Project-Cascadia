"""Wrap a raw ARM image in a minimal ELF32 with one RWX PT_LOAD at BASE.
usage: raw2elf.py IN OUT BASE [ENTRY]"""
import struct, sys
src, dst, base = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
entry = int(sys.argv[4], 0) if len(sys.argv) > 4 else base
data = open(src, "rb").read()
EH, PH = 52, 32
off = 0x1000
ehdr = struct.pack("<16sHHIIIIIHHHHHH",
    b"\x7fELF\x01\x01\x01" + b"\0" * 9, 2, 40, 1, entry, EH, 0, 0x05000000, EH, PH, 1, 0, 0, 0)
phdr = struct.pack("<IIIIIIII", 1, off, base, base, len(data), len(data), 7, 0x1000)
out = ehdr + phdr
out += b"\0" * (off - len(out)) + data
open(dst, "wb").write(out)
print(dst, len(out))
