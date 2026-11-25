#!/bin/bash
# Make sure the rebuilt bluetooth.ko exports exactly the same symbol CRCs as
# the distribution's bluetooth.ko, so the stock btusb, hidp, rfcomm, ...
# modules keep loading against it. A mismatch means the downloaded source
# does not match the running kernel (e.g. a distro patch touched Bluetooth).
#
# Usage: check-symvers.sh <kernel-build-dir> <module-build-dir>
set -euo pipefail

KDIR=${1:?}
MDIR=${2:?}
kern="$KDIR/Module.symvers"
ours="$MDIR/Module.symvers"

if [[ ! -s $kern ]]; then
	echo "bt-l2cap-encrypt-fix: $kern missing, skipping CRC check" >&2
	exit 0
fi

# CRC <tab> symbol <tab> module <tab> export type [<tab> namespace]
awk -F'\t' '
	FNR == NR { if ($3 == "net/bluetooth/bluetooth") k[$2] = $1; next }
	$3 ~ /(^|\/)bluetooth$/ {
		n++
		if (!($2 in k)) { printf "  new export: %s\n", $2; bad++ }
		else if (k[$2] != $1) { printf "  CRC mismatch: %s (%s != %s)\n", $2, $1, k[$2]; bad++ }
	}
	END {
		if (n == 0) { print "bt-l2cap-encrypt-fix: no bluetooth exports found to compare" > "/dev/stderr"; exit 0 }
		if (bad) { printf "bt-l2cap-encrypt-fix: %d of %d exported symbols differ from the running kernel; refusing to install\n", bad, n > "/dev/stderr"; exit 1 }
		printf "bt-l2cap-encrypt-fix: all %d exported symbol CRCs match the stock module\n", n > "/dev/stderr"
	}
' "$kern" "$ours"
