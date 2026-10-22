# Per-board constants for the boot chain and the firmware pulled out of the IPSW.
#
# Sourced by ./cascadia on the host and by scripts/build-firmware.sh inside the
# build container; both set ROOT first.  BOARD comes from the environment, else
# from a .board file at the repository root, else p105.
#
#   p105  iPad mini 1 Wi-Fi  (iPad2,5)   the board this port was written on
#   p106  iPad mini 1 GSM    (iPad2,6)   docs/P106.md
#
# p106 is p105 plus a baseband (Mav5 over HSIC) and a debug UART.  On iOS 8.4.1
# (12H321) the two iBSS/iBEC builds are the same iBoot-2261.30.37 code; they
# differ only in the board name, one ID byte, the GPIO pad tables (baseband and
# uart4 pins) and a build hash.  So the auto-go hook's offsets hold on both, and
# what changes here is the IPSW, its keys and the reference hashes.

if [ -z "${BOARD:-}" ]; then
    if [ -f "$ROOT/.board" ]; then
        BOARD=$(tr -d ' \t\r\n' < "$ROOT/.board")
    else
        BOARD=p105
    fi
fi

# The GPU microkernel and the 2D pack are computed from the IMGSGX543 kext in
# p105's kernelcache (tools/sgx/mkpack.py works on its addresses).  The SoC and
# its GPU are the same on every A5 iPad mini, but each board's kernelcache
# prelinks the kext somewhere else (p106: +0x6000, after the baseband kexts),
# so other boards take that one file from p105's IPSW.
P105_IPSW_URL="https://secure-appldnld.apple.com/ios8.4.1/031-31249-20150812-75235CC6-3C8F-11E5-848D-BE1A3A53DB92/iPad2,5_8.4.1_12H321_Restore.ipsw"
P105_KERNELCACHE="kernelcache.release.p105"

case "$BOARD" in
p105)
    MODEL="iPad2,5"
    IPSW_NAME="iPad2,5_8.4.1_12H321_Restore.ipsw"
    IPSW_URL="$P105_IPSW_URL"
    # Public firmware keys for iPad2,5 / 12H321.  These are not secret: they are
    # published in the community key database and are useless without the device.
    IBSS_IV="b21abc8689b0dea8f6e613f9f970e241"
    IBSS_KEY="b9ed63e4a31f5d9d4d7dddc527e65fd31d1ea48c70204e6b44551c1e6dfc52b5"
    IBEC_IV="8460cab6348e74ba7134ba0f9462b632"
    IBEC_KEY="485ddb5f7e70cecfc25c036f812641b9e55bd97783de1488306e3a80abf6950b"
    ROOTFS_DMG="058-24036-023.dmg"
    ROOTFS_KEY="21862ddcc49a861ffda17f7c6eca65355d2d1e762026cca60aabc726cd48b9e4cff214ff"
    # Reference hashes; scripts/build-firmware.sh explains each one.
    KNOWN_IBEC_PLAIN_MD5="b7e502c0262660b68adac4fe4e764b1b"
    KNOWN_IBSS_MD5="8b6dcc510c0ab303d67495978f4eb523"
    KNOWN_MTPROPS_MD5="807fdbc8816df68cf5d57a3964bd8400"
    MTPROPS_SRC=/usr/share/firmware/multitouch/P105.mtprops
    ;;
p106)
    MODEL="iPad2,6"
    IPSW_NAME="iPad2,6_8.4.1_12H321_Restore.ipsw"
    IPSW_URL="https://secure-appldnld.apple.com/ios8.4.1/031-31278-20150812-751FA1F8-3C8F-11E5-9856-BF1A3A53DB92/$IPSW_NAME"
    # Public firmware keys for iPad2,6 / 12H321 (api.ipsw.me/v4/keys/ipsw/iPad2,6/12H321).
    IBSS_IV="56231fd62c6296ed0c8c411bcef602e0"
    IBSS_KEY="cdb2142489e5e936fa8f3540bd036f62ed0f27ddb6fec96b9fbfec5a65bc5f17"
    IBEC_IV="4d59863b07ec59662ddb4872d4fd6909"
    IBEC_KEY="b70e6a9abacc46dc6a7bb55c09d7338d34acad2eed33df6db4d47f5694f978b9"
    ROOTFS_DMG="058-24261-023.dmg"
    ROOTFS_KEY="1b84c248aa18483f61723f8678da927a2938b6f8528afe9e0509c3296bfb2fdabb76435c"
    # From the first iPad2,6 that booted Linux (2026-10-21).
    KNOWN_IBEC_PLAIN_MD5="c66479581b353b9b429da2900daaf183"
    KNOWN_IBSS_MD5="6cb60375e03e513d1fffd0c65b17198f"
    # The digitizer is the same part (the p106 ADT also says multi-touch,p105):
    # p106's rootfs names the file P106.mtprops, and its bytes are p105's
    # P105.mtprops exactly.  It keeps the P105 name on the Linux side.
    KNOWN_MTPROPS_MD5="807fdbc8816df68cf5d57a3964bd8400"
    MTPROPS_SRC=/usr/share/firmware/multitouch/P106.mtprops
    ;;
*)
    echo "error: unknown BOARD '$BOARD' -- p105 (iPad2,5) or p106 (iPad2,6)" >&2
    exit 1
    ;;
esac

DTS_NAME="${BOARD}ap"
