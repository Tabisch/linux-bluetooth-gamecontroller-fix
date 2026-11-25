#!/bin/bash
# Remove the patched Bluetooth module and go back to the stock Fedora one.
set -euo pipefail

NAME=bt-l2cap-encrypt-fix
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

if command -v dkms >/dev/null; then
	for v in $(dkms status "$NAME" 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\).*|\1|p" | sort -u); do
		dkms remove "$NAME/$v" --all || true
		rm -rf "/usr/src/$NAME-$v"
	done
fi
rm -f "/etc/depmod.d/$NAME.conf"
rm -rf "/var/cache/$NAME"
depmod -a
echo "Removed. Reboot to load the stock bluetooth module again."
