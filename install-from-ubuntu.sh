#!/bin/sh
# (Re)install NixOS from the running Ubuntu: ephemeral @nixos root + @persist, @home-nixos, shared @nix,
# systemd-boot on the shared ESP. Re-runnable. Recovery path while Ubuntu still exists; on NixOS itself just use
# `sudo nixos-rebuild switch`.
#
# This repo lives in @persist (NixOS: /etc/nixos). From Ubuntu:
#   sudo mkdir -p /mnt/nixos-persist
#   sudo mount -o subvol=@persist UUID=b9218cc9-197b-4d2a-8013-3deee2e6147c /mnt/nixos-persist
#   sudo /mnt/nixos-persist/etc/nixos/install-from-ubuntu.sh
#
# First run after the GRUB-chain era (generations booted via Ubuntu's GRUB) also:
#   - seeds /persist from that root (machine-id, uid map, Bluetooth, fprint, NetworkManager, GDM, ...),
#   - keeps that root as @nixos-pre-impermanence and its profile links in /nix/var/nix/profiles/old-grub-chain/.
# The UEFI entry for systemd-boot is NOT created here (needs the RC optional data, see README).
set -eu

UUID=b9218cc9-197b-4d2a-8013-3deee2e6147c
ESP_UUID=A48E-20FE
ROOT=/mnt/nixos-root
TOP=/mnt/nixos-btrfs-top
OPTS=compress=zstd:1,noatime
FLAKE=$(dirname "$(readlink -f "$0")")
USER_NAME=seqre
PROFILES=/nix/var/nix/profiles

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

# Only unmount what this script mounted (it may itself be running from a mount of @persist).
MOUNTED=""
domount() { # mountpoint, mount args...
	m=$1; shift
	mkdir -p "$m"
	mountpoint -q "$m" && return 0
	mount "$@" "$m"
	MOUNTED="$m $MOUNTED"
}
cleanup() {
	for m in $MOUNTED; do umount "$m" || echo "could not unmount $m" >&2; done
	return 0
}
trap cleanup EXIT

domount "$TOP" -o subvolid=5 "UUID=$UUID"

echo ">> building the system"
system=$(nix build --no-link --print-out-paths "$FLAKE#toplevel")
echo "   $system"

echo ">> @persist"
[ -e "$TOP/@persist" ] || btrfs subvolume create "$TOP/@persist"
P="$TOP/@persist"

if [ -e "$TOP/@nixos" ] && [ ! -e "$TOP/@nixos-pre-impermanence" ]; then
	echo ">> first run: seeding /persist from the old root, keeping it as @nixos-pre-impermanence"
	O="$TOP/@nixos"
	for d in var/lib/nixos var/lib/systemd var/lib/bluetooth var/lib/fprint var/lib/NetworkManager \
		var/lib/AccountsService var/lib/gdm var/lib/colord var/lib/upower var/lib/power-profiles-daemon \
		var/lib/udisks2 etc/NetworkManager/system-connections; do
		if [ -d "$O/$d" ] && [ ! -e "$P/$d" ]; then
			mkdir -p "$P/$(dirname "$d")"
			cp -a --reflink=auto "$O/$d" "$P/$d"
			echo "   $d"
		fi
	done
	rm -rf "$P/var/lib/systemd/ephemeral-trees"
	[ -e "$P/etc/machine-id" ] || { mkdir -p "$P/etc"; cp -a "$O/etc/machine-id" "$P/etc/machine-id"; }
	mv "$TOP/@nixos" "$TOP/@nixos-pre-impermanence"

	# Old generations booted through Ubuntu's GRUB with a mutable root; systemd-boot must not list them.
	mkdir -p "$PROFILES/old-grub-chain"
	for l in "$PROFILES"/system "$PROFILES"/system-*-link; do
		[ -L "$l" ] && mv "$l" "$PROFILES/old-grub-chain/"
	done
fi

# Not copied from Ubuntu's NetworkManager if the old root already had the profile.
if [ ! -d "$P/etc/NetworkManager/system-connections" ]; then
	install -d -m 700 "$P/etc/NetworkManager/system-connections"
	for f in /run/NetworkManager/system-connections/netplan-*.nmconnection; do
		[ -f "$f" ] || continue
		install -m 600 "$f" "$P/etc/NetworkManager/system-connections/$(basename "$f" | sed 's/^netplan-NM-[0-9a-f-]*-//; s/%20/ /g')"
	done
fi
[ -d "$P/var/lib/fprint/$USER_NAME" ] || { mkdir -p "$P/var/lib/fprint"; cp -a "/var/lib/fprint/$USER_NAME" "$P/var/lib/fprint/"; }

echo ">> $USER_NAME's password hash (same as Ubuntu) -> /persist/secrets"
install -d -m 700 "$P/secrets"
getent shadow "$USER_NAME" | cut -d: -f2 > "$P/secrets/$USER_NAME.passwd.new"
chmod 400 "$P/secrets/$USER_NAME.passwd.new"
mv "$P/secrets/$USER_NAME.passwd.new" "$P/secrets/$USER_NAME.passwd"

echo ">> snapper .snapshots subvolumes (modules/snapshots.nix)"
[ -e "$TOP/@home-nixos" ] || btrfs subvolume create "$TOP/@home-nixos"
for s in @home-nixos @persist; do
	[ -e "$TOP/$s/.snapshots" ] || { btrfs subvolume create "$TOP/$s/.snapshots"; chmod 750 "$TOP/$s/.snapshots"; }
done

echo ">> fresh @nixos"
[ -e "$TOP/@nixos" ] || btrfs subvolume create "$TOP/@nixos"

domount "$ROOT" -o "subvol=@nixos,$OPTS" "UUID=$UUID"
domount "$ROOT/persist" -o "subvol=@persist,$OPTS" "UUID=$UUID"
domount "$ROOT/nix" -o "subvol=@nix,$OPTS" "UUID=$UUID"
domount "$ROOT/home" -o "subvol=@home-nixos,$OPTS" "UUID=$UUID"
domount "$ROOT/boot" -o fmask=0077,dmask=0077 "UUID=$ESP_UUID"

echo ">> nixos-install (systemd-boot onto the ESP)"
tools=$(nix build --no-link --print-out-paths --inputs-from "$FLAKE" nixpkgs#nixos-install-tools)
"$tools/bin/nixos-install" --root "$ROOT" --system "$system" --no-root-passwd --no-channel-copy

echo ">> ESP now"
ls "$ROOT/boot" "$ROOT/boot/EFI" "$ROOT/boot/loader/entries"
df -h "$ROOT/boot"
