/* pmu-input-limit -- raise the D1946's USB input current limit at boot.
 *
 * Under Linux the PMU keeps register 0x3d (input current limit) at code 0x02,
 * 75 + ceil(2 * 100 / 8) = 100 mA, below what the system draws, so the
 * battery discharges on a USB host even though the charger itself is enabled
 * (0x3f bit 0x40 clear).  iOS sets 500 mA on the same cable.  This sets the
 * same 500 mA (code 0x22) when register 0x0a reports a USB source (bit 3),
 * which is how AppleD1946PMU classifies one; docs/research in PR #8 decodes
 * both registers from the 12H321 kext.
 *
 * Only the input limit is touched: charge current, charge voltage,
 * termination and the PMU's own protections are left as they are.  The USB
 * gadget declares the matching 500 mA (g_cdc.usb2_maxpower=500).
 *
 *   pmu-input-limit [-n] [500|1500]
 *
 * sets the limit (default 500 mA) if a USB source is present; -n only
 * reports.  1500 mA is for a wall charger, which never enumerates the
 * gadget: on a 5 V / 3 A charger it took the battery from -428 to +660 mA.
 * p105-charge-watch picks the value.
 *
 * Prints one line, for /dev/kmsg.  Exit status 0 when the limit is set (or
 * already was), 2 when there is no USB source, 1 on any I2C error, with
 * nothing written after a failed read.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PMU_BUS		"/dev/i2c-0"
#define PMU_ADDR	0x3c
#define REG_SOURCE	0x0a
#define  SOURCE_USB	0x08
#define REG_ILIM	0x3d
#define ILIM_500MA	0x22
#define ILIM_1500MA	0x72

static int smbus(int fd, char rw, unsigned char reg, unsigned char *val)
{
	union i2c_smbus_data data;
	struct i2c_smbus_ioctl_data args = {
		.read_write = rw, .command = reg,
		.size = I2C_SMBUS_BYTE_DATA, .data = &data,
	};

	if (rw == I2C_SMBUS_WRITE)
		data.byte = *val;
	if (ioctl(fd, I2C_SMBUS, &args) < 0)
		return -errno;
	if (rw == I2C_SMBUS_READ)
		*val = data.byte;
	return 0;
}

static unsigned int ilim_ma(unsigned char code)
{
	return 75 + (code * 100 + 7) / 8;
}

int main(int argc, char **argv)
{
	int dry = 0, fd, ret, i;
	unsigned char src, ilim, want = ILIM_500MA;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-n"))
			dry = 1;
		else if (!strcmp(argv[i], "500"))
			want = ILIM_500MA;
		else if (!strcmp(argv[i], "1500"))
			want = ILIM_1500MA;
		else {
			printf("usage: pmu-input-limit [-n] [500|1500]\n");
			return 1;
		}
	}

	fd = open(PMU_BUS, O_RDWR);
	if (fd < 0) {
		printf("pmu-input-limit: %s: %s\n", PMU_BUS, strerror(errno));
		return 1;
	}
	/* The PMU is bound to apple-pmu-i2c; force, as i2cget -f does. */
	if (ioctl(fd, I2C_SLAVE_FORCE, PMU_ADDR) < 0) {
		printf("pmu-input-limit: address 0x%02x: %s\n", PMU_ADDR, strerror(errno));
		return 1;
	}
	ret = smbus(fd, I2C_SMBUS_READ, REG_SOURCE, &src);
	if (!ret)
		ret = smbus(fd, I2C_SMBUS_READ, REG_ILIM, &ilim);
	if (ret) {
		printf("pmu-input-limit: read failed: %s\n", strerror(-ret));
		return 1;
	}
	if (!(src & SOURCE_USB)) {
		printf("pmu-input-limit: no USB source (0x0a=0x%02x), input limit left at %u mA\n",
		       src, ilim_ma(ilim));
		return 2;
	}
	if (ilim == want) {
		printf("pmu-input-limit: USB source, input limit already %u mA\n", ilim_ma(ilim));
		return 0;
	}
	if (dry) {
		printf("pmu-input-limit: USB source, would set input limit %u -> %u mA\n",
		       ilim_ma(ilim), ilim_ma(want));
		return 0;
	}
	ret = smbus(fd, I2C_SMBUS_WRITE, REG_ILIM, &want);
	if (!ret)
		ret = smbus(fd, I2C_SMBUS_READ, REG_ILIM, &ilim);
	if (ret) {
		printf("pmu-input-limit: write failed: %s\n", strerror(-ret));
		return 1;
	}
	printf("pmu-input-limit: USB source, input limit now %u mA (0x3d=0x%02x)\n",
	       ilim_ma(ilim), ilim);
	return ilim == want ? 0 : 1;
}
