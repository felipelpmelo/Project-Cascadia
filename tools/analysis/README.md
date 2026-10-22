# Firmware analysis scripts

The scripts used to establish that the iPad2,6 (p106) runs this port
(docs/P106.md).  They work on Apple's own 12H321 images and need no device;
nothing here ships Apple firmware.  Standard library Python, plus `openssl`
for `img3.py`; `rootfs-find.py` needs pycryptodome (the build image has it).

| Script | What |
|---|---|
| `ipsw-remote.py URL OUT [--list] [GLOB...]` | list or extract members of a remote IPSW with HTTP range requests, without downloading the whole file |
| `img3.py IN OUT IV KEY` | decrypt an IMG3 payload; a kernelcache is also LZSS-decompressed |
| `adt.py dump FILE` / `adt.py diff A B` | print or diff an Apple Device Tree |
| `adt-semdiff.py A B` | diff two device trees with phandles resolved to node paths, so only real hardware differences remain |
| `kextlist.py KERNELCACHE` | prelinked kexts with load address and bundle id |
| `raw2elf.py IN OUT BASE [ENTRY]` | wrap a raw ARM image (a decrypted iBEC at `0x9ff00000`) in an ELF so disassemblers that need headers open it |
| `rootfs-find.py DMG KEY REGEX...` | find files by name in an encrypted root DMG (copied out of the IPSW with `unzip -p`), with size and md5 |

Keys for 12H321 come from `https://api.ipsw.me/v4/keys/ipsw/<model>/12H321`.

## Comparing two boards

```sh
ipsw-remote.py "$URL_A" a 'Firmware/dfu/*.dfu' '*/DeviceTree.*' 'kernelcache*'
ipsw-remote.py "$URL_B" b 'Firmware/dfu/*.dfu' '*/DeviceTree.*' 'kernelcache*'
img3.py a/iBEC.p105.RELEASE.dfu a/iBEC.bin "$IV" "$KEY"      # and the rest
cmp -l a/iBEC.bin b/iBEC.bin | wc -l                          # code vs data
adt-semdiff.py a/DeviceTree.bin b/DeviceTree.bin
diff <(kextlist.py a/kc | cut -d' ' -f3) <(kextlist.py b/kc | cut -d' ' -f3)
```

For p105 against p106 this gave 80 differing iBEC bytes (board name, the two
GPIO pad tables, a build hash), four extra device-tree nodes (the modem and a
UART) and four extra kexts.
