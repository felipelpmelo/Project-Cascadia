#!/usr/bin/env bash
#
# Build the boot-chain images this port needs, from a stock IPSW.
#
#   iBSS.patched                signature patch only; stock USB receive is left
#                               alone so the host can still upload iBEC
#   iBEC.patched.autogo.dfu     signature patch plus the auto-go hook, packed
#                               the way the stock image is: encrypted, with a
#                               KBAG.  This is the one the checkm8 route sends
#   iBEC.patched.autogo.plain.dfu
#                               the same patched iBEC, packed WITHOUT
#                               encryption.  --kdfu needs this one: after iOS
#                               has booted the AES GID key is gone, so a KBAG
#                               decrypts to nothing and the iBSS jumps into
#                               garbage (scripts/img3pack.py has the detail)
#   P105.mtprops                the digitizer's firmware, out of the root
#                               filesystem (scripts/rootfs-extract.py); touch
#                               needs it and ./cascadia build puts it in the
#                               image
#   brcmfmac4334.bin            the Wi-Fi chip's firmware, wifi/4334b1/borg.trx
#                               from the same place ("borg" is the ADT's
#                               module-instance), a TRX image -- what
#                               brcmfmac downloads over USB -- with the
#                               module's NVRAM appended inside it
#                               (scripts/trx-add-nvram.py): without it the
#                               firmware is downloaded and never comes up
#   BCM4334B0.hcd               the same chip's Bluetooth patchram, cut out of
#                               /usr/sbin/BlueTool, which carries one per
#                               module (scripts/extract-bt-firmware.py)
#   sgx543.fw                   the GPU's microkernel and PDS templates, out of
#                               the kernelcache's IMGSGX543 kext
#                               (scripts/extract-sgx-firmware.py)
#   kernelcache.12H321.macho    the decrypted kernelcache itself; the GPU's 2D
#                               pack is computed from its GPU kext
#                               (tools/sgx/mkpack.py, docs/GPU.md)
#   gl-event.pds                the 3D pass's event PDS program, a template in
#                               iOS's GL driver (dyld shared cache), for the
#                               same pack
#
# Runs INSIDE the build container (see ./cascadia firmware): the image carries
# pycryptodome, capstone and an iBoot32Patcher built from source, so the result
# is identical on a macOS and a Linux host and nothing outside this repository
# and the user's own IPSW is needed.
#
# Pinned to iOS 8.4.1 / 12H321.  That is not laziness: the auto-go hook patches a
# specific address inside this exact iBEC build (scripts/patch-ibec-autogo.py
# explains which and why), and the decryption keys are that build's.  Another
# firmware needs both re-derived.  The board (p105 = iPad2,5, p106 = iPad2,6) is
# picked in scripts/board.sh; both boards' 12H321 iBEC carry the same code.
#
# Why an auto-go hook at all, rather than iBoot32Patcher's own -c "go": that
# command runs as soon as it is parsed.  The 64 KB memory probe survived it; a
# 13 MB staging bundle does not -- the loader ran after the first 32 KB chunk,
# before the kernel had landed, which shows up as a magenta screen and no boot.
# The hook fires on the completion whose byte count is short, i.e. at EOF.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# IPSW keys, rootfs name and reference hashes for the selected board.
. "$ROOT/scripts/board.sh"
IPSW="${IPSW:-$ROOT/$IPSW_NAME}"
OUT="$ROOT/build/firmware"

# Per board in iOS (scripts/board.sh); always P105.mtprops here, the name the
# Linux side (tools/z2-boot.c, ./cascadia build) loads.
MTPROPS="$MTPROPS_SRC"
WIFI_FW=/usr/share/firmware/wifi/4334b1/borg.trx
# The NVRAM goes with the firmware, per module.  The chip names itself
# "s=B3 M=HEIN m=2.6 V=t" (4334B3, TDK), and the iOS 8.4.1 Wi-Fi driver's own
# table, "Heineken - 4334B3 - TDK", picks by the ADT's module-instance: borg
# is borg.trx with borg-t-st.txt (heineken-t-st.txt belongs to centennial.trx,
# the default).  borg.trx with the heineken file came up, and halted on the
# first command -- that file lacks swdiv_en/swdiv_gpio, which a firmware built
# with swdiv wants, and has regrev 9 where borg's has 14.  WIFI_NVRAM= picks
# another file from wifi/4334b1/.
WIFI_NVRAM="${WIFI_NVRAM:-borg-t-st.txt}"
# Bluetooth's patchram is inside /usr/sbin/BlueTool, one image per module
# (scripts/extract-bt-firmware.py), and the module is the Wi-Fi one: Borg,
# made by TDK, as WIFI_NVRAM says.  BT_MODULE= picks another ("Borg USI").
BT_MODULE="${BT_MODULE:-Borg TDK}"
# The module files carry no MAC address -- iOS adds the one in syscfg -- and
# without macaddr= the firmware's wl half never attaches.  Locally administered,
# the same family as the USB gadget's pair in the dts; WIFI_MAC= sets another
# (the iPad's own is under Settings > General > About > Wi-Fi Address).
WIFI_MAC="${WIFI_MAC:-02:10:5a:05:00:03}"

BOOTARGS="${BOOTARGS:-cs_enforcement_disable=1 debug=0x14}"

# Reference hashes, so a regenerated image can be compared rather than trusted.
#
# The iBEC one is of the PLAINTEXT, before it is repacked into an img3, and that
# is deliberate.  The .dfu that this device has actually been booting is a
# binary preserved back in August by restore-known-good.sh, and the auto-go
# script has changed since: its trampoline now differs from the one in that
# file, starting two bytes in.  Everything downstream of that differs too,
# because the img3 payload is AES-CBC and a single changed block poisons the
# rest -- which is why comparing the .dfu says nothing useful about whether the
# pipeline is correct.  The plaintext hash does: it is what the author's own
# current scripts produce, verified byte-for-byte.
#
# The .dfu this produces is not byte-identical to the preserved August image,
# and that is expected rather than a problem: the auto-go script changed in
# between.  This build has since been flashed and the device booted from it, so
# it is the tested one now.
#
# The mtprops one is of the same bytes iOS itself has at that path on the iPad
# (read there over ssh and compared).  The values are in scripts/board.sh.

fail() { echo "error: $*" >&2; exit 1; }
md5of() { md5sum "$1" | cut -d' ' -f1; }

echo "==> board: $BOARD ($MODEL)"
[ -f "$IPSW" ] || fail "no IPSW at $IPSW -- pass IPSW=/path/to/$IPSW_NAME"

PATCHER="${PATCHER:-/usr/local/bin/iBoot32Patcher}"
command -v "$PATCHER" >/dev/null 2>&1 || [ -x "$PATCHER" ] \
    || fail "no iBoot32Patcher at $PATCHER -- rebuild the image: docker rmi cascadia-build"

mkdir -p "$OUT"

build_one() {
    local name="$1" iv="$2" key="$3"
    echo "==> $name: extract, decrypt, patch"
    unzip -o -j "$IPSW" "Firmware/dfu/${name}.${BOARD}.RELEASE.dfu" -d "$OUT" >/dev/null \
        || fail "$name not found in $IPSW -- is this an $MODEL 8.4.1 IPSW?"
    python3 "$ROOT/scripts/img3decrypt.py" \
        "$OUT/${name}.${BOARD}.RELEASE.dfu" "$OUT/${name}.dec" "$iv" "$key"
    "$PATCHER" "$OUT/${name}.dec" "$OUT/${name}.patched" -b "$BOOTARGS" >/dev/null
}

build_one iBSS "$IBSS_IV" "$IBSS_KEY"
# Signature patch only.  The park hooks that once lived here rebooted the device
# straight back into iOS, and iBSS has to keep its stock USB receive path or
# there is no way to upload iBEC over the cable.
python3 "$ROOT/scripts/verify-ibss-clean.py" "$OUT/iBSS.patched"

build_one iBEC "$IBEC_IV" "$IBEC_KEY"
echo "==> iBEC: auto-go hook"
python3 "$ROOT/scripts/patch-ibec-autogo.py" "$OUT/iBEC.patched" "$OUT/iBEC.autogo"
echo "==> iBEC: repack as img3 (encrypted -- the checkm8 route)"
python3 "$ROOT/scripts/img3encrypt.py" \
    "$OUT/iBEC.${BOARD}.RELEASE.dfu" "$OUT/iBEC.autogo" \
    "$OUT/iBEC.patched.autogo.dfu" "$IBEC_IV" "$IBEC_KEY"
echo "==> iBEC: repack as img3 (plaintext -- the kDFU route)"
python3 "$ROOT/scripts/img3pack.py" \
    "$OUT/iBEC.${BOARD}.RELEASE.dfu" "$OUT/iBEC.autogo" \
    "$OUT/iBEC.patched.autogo.plain.dfu"

echo "==> touch, Wi-Fi and Bluetooth firmware out of the root filesystem"
python3 "$ROOT/scripts/rootfs-extract.py" "$IPSW" "$ROOTFS_DMG" "$ROOTFS_KEY" \
    "$MTPROPS" "$OUT/P105.mtprops" "$WIFI_FW" "$OUT/borg.trx" \
    "/usr/share/firmware/wifi/4334b1/$WIFI_NVRAM" "$OUT/brcmfmac4334-nvram.txt" \
    /usr/sbin/BlueTool "$OUT/BlueTool"
python3 "$ROOT/scripts/trx-add-nvram.py" "$OUT/borg.trx" "$OUT/brcmfmac4334-nvram.txt" \
    "$OUT/brcmfmac4334.bin" "$WIFI_MAC"
python3 "$ROOT/scripts/extract-bt-firmware.py" "$OUT/BlueTool" "$BT_MODULE" "$OUT/BCM4334B0.hcd"
rm -f "$OUT/BlueTool"
if [ "$BT_MODULE" = "Borg TDK" ]; then
    echo "b6791a67141f1a16447e916237180a049b89dfaab9c38451b33864dbb6a50dda  $OUT/BCM4334B0.hcd" \
        | sha256sum -c --quiet - || fail "BCM4334B0.hcd is not 12H321's Borg TDK patchram"
fi

# Always p105's kernelcache: tools/sgx/mkpack.py works on that kernelcache's
# addresses, and other boards prelink the same GPU kext elsewhere
# (scripts/board.sh).  On p105 it comes out of the IPSW; on other boards
# ./cascadia firmware fetches the one file into build/firmware first.
echo "==> GPU microkernel out of p105's kernelcache"
if [ "$BOARD" = p105 ]; then
    SGX_SRC="$IPSW"
else
    SGX_SRC="${SGX_KERNELCACHE:-$OUT/$P105_KERNELCACHE}"
fi
if [ -f "$SGX_SRC" ]; then
    python3 "$ROOT/scripts/extract-sgx-firmware.py" "$SGX_SRC" "$OUT/sgx543.fw" \
        "$OUT/kernelcache.12H321.macho"
else
    echo "    note: no $SGX_SRC -- skipping the GPU firmware; ./cascadia firmware fetches it"
fi

# The 3D pass's event PDS program: a template in iOS's GL driver
# (IMGSGX543GLDriver, in the dyld shared cache), 0xa8 bytes the 2D pack
# fills in (tools/sgx/pds.py).  Only that range is read; the cache is 432 MB.
# The offset is p105's cache.  Another board's cache may lay the GL driver
# out elsewhere, so there a mismatch only costs the 3D pass, not the build.
echo "==> GPU event program out of the GL driver"
GL_EVENT_SHA256="a1b855d41993968b40005e886f7ac11c8c3abb42aa0987e005eec4e6cb2a2285"
if python3 "$ROOT/scripts/rootfs-extract.py" "$IPSW" "$ROOTFS_DMG" "$ROOTFS_KEY" \
        "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7@46ebd8+a8" "$OUT/gl-event.pds" \
    && echo "$GL_EVENT_SHA256  $OUT/gl-event.pds" | sha256sum -c --quiet - 2>/dev/null; then
    :
elif [ "$BOARD" = p105 ]; then
    fail "gl-event.pds is not the 12H321 GL driver's"
else
    echo "    note: $BOARD's dyld cache has no 12H321 GL event program at p105's offset;"
    echo "          the 3D pass (./cascadia gpu) needs it, everything else does not"
    rm -f "$OUT/gl-event.pds"
fi

echo
rc=0
for pair in "iBSS.patched:$KNOWN_IBSS_MD5" "iBEC.autogo:$KNOWN_IBEC_PLAIN_MD5" "P105.mtprops:$KNOWN_MTPROPS_MD5"; do
    f=${pair%%:*}; want=${pair##*:}; got=$(md5of "$OUT/$f")
    if [ -z "$want" ]; then
        echo "    new:  $f is $got -- no $BOARD reference yet (scripts/board.sh)"
    elif [ "$got" = "$want" ]; then
        echo "    ok: $f reproduces the reference byte for byte"
    else
        echo "    MISMATCH: $f is $got, expected $want"
        rc=1
    fi
done
if [ "$rc" -ne 0 ]; then
    cat <<'EOF'

    Something in the chain changed.  The decrypted input, iBoot32Patcher's
    output and the auto-go patch are each deterministic, so a mismatch here
    points at one of them rather than at noise.
EOF
elif [ "$BOARD" = p105 ]; then
    cat <<'EOF'

    This differs from the preserved August .dfu, because the auto-go script
    changed after that image was saved.  It has been flashed and the device
    booted from it.  ./cascadia flash --known-good still sends the old one if
    you ever need to tell a bad build from a bad bench.
EOF
elif [ -z "$KNOWN_IBSS_MD5" ] || [ -z "$KNOWN_IBEC_PLAIN_MD5" ]; then
    cat <<EOF

    No $BOARD device has booted from these yet.  Once one has, the hashes
    printed above become the references in scripts/board.sh.
EOF
fi

echo
ls -l "$OUT/iBSS.patched" "$OUT/iBEC.patched.autogo.dfu" \
      "$OUT/iBEC.patched.autogo.plain.dfu" "$OUT/P105.mtprops" "$OUT/brcmfmac4334.bin" \
      "$OUT/BCM4334B0.hcd"
for f in sgx543.fw kernelcache.12H321.macho gl-event.pds; do
    if [ -f "$OUT/$f" ]; then ls -l "$OUT/$f"; else echo "    (no $f -- GPU only)"; fi
done
