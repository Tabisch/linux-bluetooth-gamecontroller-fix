#!/bin/bash
# Install the patched Bluetooth module on Fedora via DKMS.
#
#   sudo ./install.sh            build + install for the running kernel
#   sudo ./install.sh --reload   ...and swap the module in right away (no reboot)
#   ./install.sh --status        show which bluetooth.ko is installed / loaded
set -euo pipefail

NAME=bt-l2cap-encrypt-fix
VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/dkms.conf")
HERE=$(cd "$(dirname "$0")" && pwd)
KVER=$(uname -r)
DEPMOD_CONF=/etc/depmod.d/$NAME.conf

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

status() {
	echo "kernel:            $KVER"
	echo "module on disk:    $(modinfo -k "$KVER" -n bluetooth 2>/dev/null || echo none)"
	if [[ -r /sys/module/bluetooth/srcversion ]]; then
		loaded=$(cat /sys/module/bluetooth/srcversion)
		disk=$(modinfo -k "$KVER" -F srcversion bluetooth 2>/dev/null || true)
		echo "loaded srcversion: $loaded"
		if [[ $(modinfo -k "$KVER" -n bluetooth 2>/dev/null) == */kernel/net/bluetooth/* ]]; then
			echo "state:             stock module (fix NOT active)"
		elif [[ $loaded == "$disk" ]]; then
			echo "state:             patched module loaded (fix active)"
		else
			echo "state:             patched module installed, but the old one is still loaded (reboot or --reload)"
		fi
	else
		echo "state:             bluetooth module not loaded"
	fi
	command -v dkms >/dev/null && dkms status "$NAME" || true
}

reload_bluetooth() {
	say "Reloading the Bluetooth modules"
	local mods=()
	collect() {
		local m=$1 h
		for h in /sys/module/"$m"/holders/*; do
			[[ -e $h ]] && collect "$(basename "$h")"
		done
		mods+=("$m")
	}
	[[ -d /sys/module/bluetooth ]] && collect bluetooth
	systemctl stop bluetooth.service || true
	for m in "${mods[@]}"; do
		modprobe -r "$m" 2>/dev/null || rmmod "$m" 2>/dev/null || true
	done
	if [[ -d /sys/module/bluetooth ]]; then
		warn "could not unload the old bluetooth module (still in use); please reboot"
	fi
	# Load everything back (btusb etc. pull in the new bluetooth.ko).
	for m in "${mods[@]}"; do modprobe "$m" 2>/dev/null || true; done
	modprobe btusb 2>/dev/null || true
	systemctl start bluetooth.service || true
}

case ${1:-} in
--status) status; exit 0 ;;
--reload | "") ;;
*) echo "usage: $0 [--reload|--status]" >&2; exit 2 ;;
esac

if [[ $EUID -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

say "Installing build dependencies"
pkgs=(dkms make gcc patch git curl tar xz "kernel-devel-$KVER")
missing=()
for p in "${pkgs[@]}"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((${#missing[@]})); then
	if ! dnf install -y "${missing[@]}"; then
		warn "could not install ${missing[*]}."
		warn "If kernel-devel-$KVER is not available, update your kernel (sudo dnf upgrade --refresh kernel\\*) and reboot first."
		exit 1
	fi
fi

say "Registering $NAME $VERSION with DKMS"
if dkms status "$NAME/$VERSION" | grep -q .; then
	dkms remove "$NAME/$VERSION" --all || true
fi
rm -rf "/usr/src/$NAME-$VERSION"
mkdir -p "/usr/src/$NAME-$VERSION"
cp -a "$HERE"/{dkms.conf,Makefile,patches,scripts} "/usr/src/$NAME-$VERSION/"
dkms add "$NAME/$VERSION"

say "Building for $KVER (downloads the matching Bluetooth source once)"
if ! dkms build "$NAME/$VERSION" -k "$KVER"; then
	warn "build failed; see /var/lib/dkms/$NAME/$VERSION/build/make.log"
	exit 1
fi
dkms install "$NAME/$VERSION" -k "$KVER" --force

# Make sure the DKMS copy wins over the stock module, whatever directory
# this DKMS version installs into.
path=$(find "/lib/modules/$KVER" -path "*/kernel/net/bluetooth" -prune -o \
	-name 'bluetooth.ko*' -print 2>/dev/null | head -n1)
if [[ -n $path ]]; then
	dir=$(dirname "${path#/lib/modules/$KVER/}")
	echo "override bluetooth * ${dir%%/*}" >"$DEPMOD_CONF"
	depmod -a "$KVER"
fi
say "Installed: $(modinfo -k "$KVER" -n bluetooth)"

# Secure Boot: DKMS signs the module with its own key, which must be enrolled once.
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
	pub=""
	for f in /var/lib/dkms/mok.pub /var/lib/dkms/mok.der; do [[ -f $f ]] && pub=$f && break; done
	if [[ -n $pub ]] && ! mokutil --test-key "$pub" 2>/dev/null | grep -qi "already enrolled"; then
		say "Secure Boot is on: enrolling the DKMS signing key"
		echo "Choose a one-time password. After the reboot the blue 'MOK management' screen"
		echo "appears: pick 'Enroll MOK' -> 'Continue' -> 'Yes' and enter that password."
		mokutil --import "$pub"
		warn "Reboot now to finish the key enrollment; until then the patched module cannot load."
		exit 0
	fi
fi

if [[ ${1:-} == --reload ]]; then
	reload_bluetooth
	status
else
	say "Done. Reboot (or run: sudo $0 --reload) to load the patched module."
fi
