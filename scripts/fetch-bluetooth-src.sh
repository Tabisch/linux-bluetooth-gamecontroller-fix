#!/bin/bash
# Fetch net/bluetooth/ of the upstream kernel matching a Fedora kernel
# release (e.g. 7.2.10-200.fc44.x86_64 -> tag v7.2.10) into DEST.
#
# Usage: fetch-bluetooth-src.sh <kernel-release> <dest-dir>
#
# Environment:
#   BT_FIX_KERNEL_SRC  use this local kernel source tree instead of downloading
#   BT_FIX_CACHE       cache directory (default /var/cache/bt-l2cap-encrypt-fix)
set -euo pipefail

KVER=${1:?kernel release required}
DEST=${2:?destination directory required}
CACHE=${BT_FIX_CACHE:-/var/cache/bt-l2cap-encrypt-fix}

log() { echo "bt-l2cap-encrypt-fix: $*" >&2; }

copy_from() {
	local tree=$1
	if [[ ! -f $tree/net/bluetooth/l2cap_core.c ]]; then
		log "no net/bluetooth/l2cap_core.c in $tree"
		return 1
	fi
	rm -rf "$DEST"
	mkdir -p "$DEST/net"
	cp -a "$tree/net/bluetooth" "$DEST/net/bluetooth"
}

if [[ -n ${BT_FIX_KERNEL_SRC:-} ]]; then
	log "using local kernel source $BT_FIX_KERNEL_SRC"
	copy_from "$BT_FIX_KERNEL_SRC"
	exit 0
fi

# Map the Fedora kernel release to an upstream tag.
#   7.2.10-200.fc44.x86_64       -> v7.2.10
#   7.3.0-200.fc44.x86_64        -> v7.3
#   7.4.0-0.rc4.38.fc45.x86_64   -> v7.4-rc4  (Rawhide)
base=${KVER%%-*}
rel=${KVER#*-}
IFS=. read -r maj min sub <<<"$base"
sub=${sub:-0}
if [[ $rel =~ ^0\.(rc[0-9]+) ]]; then
	tag="v$maj.$min-${BASH_REMATCH[1]}"
	tarball=""
	if [[ $rel == *git* ]]; then
		log "WARNING: $KVER is a git snapshot kernel; using $tag, which may not match exactly"
	fi
elif [[ $sub == 0 ]]; then
	tag="v$maj.$min"
	tarball="https://cdn.kernel.org/pub/linux/kernel/v$maj.x/linux-$maj.$min.tar.xz"
else
	tag="v$maj.$min.$sub"
	tarball="https://cdn.kernel.org/pub/linux/kernel/v$maj.x/linux-$maj.$min.$sub.tar.xz"
fi

cached="$CACHE/$tag"
if [[ -f $cached/net/bluetooth/l2cap_core.c ]]; then
	log "using cached source for $tag"
	copy_from "$cached"
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch_git() {
	local url=$1
	log "fetching net/bluetooth for $tag from $url"
	rm -rf "$work/git"
	git -c advice.detachedHead=false clone --quiet --depth 1 --filter=blob:none --sparse \
		--branch "$tag" "$url" "$work/git" &&
		git -C "$work/git" sparse-checkout set net/bluetooth &&
		[[ -f $work/git/net/bluetooth/l2cap_core.c ]]
}

fetch_tarball() {
	[[ -n $tarball ]] || return 1
	log "downloading $tarball (large, ~150 MB)"
	rm -rf "$work/tar" && mkdir -p "$work/tar"
	curl -fL --retry 3 "$tarball" |
		tar -xJ -C "$work/tar" --strip-components=1 --wildcards '*/net/bluetooth/*' &&
		mv "$work/tar" "$work/git"
}

if command -v git >/dev/null &&
	{ fetch_git https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git ||
	  fetch_git https://github.com/gregkh/linux.git; }; then
	:
elif fetch_tarball; then
	:
else
	log "could not download the kernel source for $tag."
	log "Point BT_FIX_KERNEL_SRC at an unpacked kernel tree and retry."
	exit 1
fi

mkdir -p "$CACHE" 2>/dev/null && {
	rm -rf "$cached"
	mkdir -p "$cached/net"
	cp -a "$work/git/net/bluetooth" "$cached/net/bluetooth"
} || log "could not write cache $CACHE (continuing)"

copy_from "$work/git"
