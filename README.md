# nixos-secomet

NixOS for the Acer Swift Go 14 AI (SFG14-01, Snapdragon X x1p42100), installed next to the working Ubuntu on the
same btrfs filesystem (`nvme0n1p5`) and the shared ESP (`nvme0n1p1`, grown to 2.2 GB). The hardware fixes are the
ones documented in `~/ISSUES.md` on Ubuntu; each file says which section it comes from.

This repo is **`/etc/nixos`** on NixOS: persisted in `@persist` (`/persist/etc/nixos`, bind-mounted by impermanence),
owned by root. Edit with sudo, apply with `sudo nixos-rebuild switch`.

**Not for a public repo:** `blobs/firmware/` holds Acer's firmware, copied from Windows. It is git-ignored and enters
the build as the flake input `acer-firmware` (`path:/etc/nixos/blobs/firmware`, pinned by hash in `flake.lock`).
After changing those files by hand, run `sudo nix flake update acer-firmware`, or the build fails with a hash mismatch.

## Layout on disk

| Subvolume                 | Ubuntu         | NixOS               |
|---------------------------|----------------|---------------------|
| `@nix`                    | `/nix` (host Nix, `nix-setup-systemd`) | `/nix` (same store, same DB) |
| `@nixos`                  | (not mounted)  | `/`, **recreated empty on every boot** |
| `@nixos-old/<timestamp>`  | (not mounted)  | previous roots, deleted after 14 days |
| `@persist`                | (not mounted)  | `/persist`: the state that survives, including this repo (`/etc/nixos`) |
| `@home-nixos`             | (not mounted)  | `/home` (persistent; dotfiles via Home Manager) |
| `@home`                   | `/home`        | (not mounted)       |
| `@swap`                   | `/swap`        | `/swap` (same swapfile) |
| `@nixos-pre-impermanence` | (not mounted)  | the first, mutable-root install; safe to delete |

`/mnt/btrfs-top` (automount) on NixOS is the btrfs top level, for looking at `@nixos-old/`.

Snapper only snapshots Ubuntu's `@`. NixOS generations are its rollback mechanism. `@nix` is shared:
a plain `nix-collect-garbage` on either side is safe (both OSes' profiles are GC roots), `nix-collect-garbage -d`
deletes old NixOS generations too.

## Impermanence

- The initrd unit `rollback-root` moves `@nixos` to `@nixos-old/<mtime>` and creates an empty `@nixos` before
  `/sysroot` is mounted.
- `environment.persistence."/persist"` bind-mounts: `/etc/nixos` (root:root 0755), `/var/log`, `/var/lib/{nixos,systemd,bluetooth,fprint,
  NetworkManager,AccountsService,gdm,colord,upower,power-profiles-daemon,udisks2}`,
  `/etc/NetworkManager/system-connections`, `/etc/machine-id`.
- Users are declarative (`users.mutableUsers = false`). `seqre`'s password hash is in `/persist/secrets/seqre.passwd`
  (root-only; copied from Ubuntu's `/etc/shadow`). To change it: `mkpasswd -m yescrypt` and write the hash there.
- Anything else written outside `/home`, `/nix` and `/persist` is gone after a reboot. To keep something, add it to
  `modules/impermanence.nix`, move the current copy into `/persist/...`, rebuild.

## Boot path

1. UEFI **`Boot0003` "NixOS (systemd-boot)"** → `\EFI\systemd\systemd-bootaa64.efi`. Created by hand with the `RC`
   optional data this firmware requires:
   `printf RC > rc.bin; efibootmgr -c -d /dev/nvme0n1 -p 1 -L "NixOS (systemd-boot)" -l '\EFI\systemd\systemd-bootaa64.efi' -@ rc.bin`
   NixOS never writes UEFI variables (`canTouchEfiVariables = false`). **Boot order:** this is Insyde firmware, which
   rebuilds `BootOrder` from its own setup list at every power-on (new entries go last). Set it in the firmware setup
   (F2 → Boot → Boot priority order); `efibootmgr -n 0003` works for one boot.
2. systemd-boot menu: NixOS generations (kernel, initrd and DTB copied to `\EFI\nixos`), "Ubuntu (shim + GRUB)",
   Windows Boot Manager (auto-detected).
3. Fallbacks: `Boot0000` (Ubuntu shim/GRUB) still exists, and Ubuntu's GRUB has "NixOS (systemd-boot)"
   (`/etc/grub.d/46_nixos`), which chainloads systemd-boot. `\EFI\BOOT\BOOTAA64.EFI` is systemd-boot now (bootctl
   install replaced the copy of Ubuntu's shim; old ESP: `/var/backups/esp-before-systemd-boot-2026-10-03.tar` on
   Ubuntu).
4. GRUB's `cutmem` workaround is not applied by systemd-boot. RAM on this 16 GB model ends at `0xbffffffff`, below
   the cut range.

## What's where

- `pkgs/kernel/`: jg 7.2.2-jg-0 (same source as Ubuntu's kernel) with Ubuntu's config minus module signing and the
  lockdown LSM, plus two patches: PS8830 retimer reset polarity, x1p42100 CAMSS.
- `pkgs/dtb/`: kernel DTB + camera, fingerprint and cleanup overlays + the BT property deletions. Byte-identical to
  Ubuntu's `/boot/dtb-cleanup`.
- `pkgs/ov05c10/`: the camera sensor driver (out-of-tree module).
- `pkgs/acer-firmware.nix`: ADSP (battery), CDSP, GPU zap firmware.
- `pkgs/acer-ec/`: `ec-rw`, `ec-dump`, `acer-ec-hostmode` (keyboard backlight).
- `modules/sfg14-hardware.nix`: kernel params, initrd modules, DT, firmware, udev, EC service.
- `modules/impermanence.nix`: rollback unit + persisted paths.
- `modules/camera.nix`: libcamera with the lens shading patch (`pkgs/libcamera/`) for PipeWire/WirePlumber/`cam`,
  OV05C10 tuning file (`files/ov05c10.yaml`).
- `modules/fingerprint.nix`: SDCP libfprint/fprintd.
- `modules/firmware-sync.nix`, `modules/snapshots.nix`: see below.
- `secomet.nix`: the host config: boot loader, filesystems, GNOME, users, Home Manager, Nix GC.
- `home/seqre.nix`: Home Manager config for seqre, linked as `~/configuration.nix`.
- `install-from-ubuntu.sh`: (re)install from Ubuntu.

## Firmware sync from Windows

`modules/firmware-sync.nix`: `qcom-firmware-sync.timer` (daily; a missed run happens at the next boot) mounts Windows read-only,
takes the newest DriverStore copy of each firmware file (same list and pick as Ubuntu's `qcom-firmware-extract` 21)
and compares it with `blobs/firmware`. On a change it updates `blobs/firmware`, re-locks the `acer-firmware` input and runs
`nixos-rebuild boot` on the current default generation's recorded flake source (`/nix/var/nix/profiles/system/flake-source`,
every generation has one) with only the firmware swapped, so uncommitted edits in `/etc/nixos` are never built
automatically. New firmware is used from the next boot. Logs: `journalctl -u qcom-firmware-sync`. Plain NTFS only
(no BitLocker).

## Snapshots

`modules/snapshots.nix`: snapper configs `home` (`/home`, seqre may use it) and `persist` (`/persist`), hourly
timeline, kept 5 hourly / 7 daily / 2 weekly / 1 monthly. Snapshots are in `/home/.snapshots` and
`/persist/.snapshots` (subvolumes). `snapper -c home list`, `sudo snapper -c persist list`.

**Future:** consider btrbk: the same local snapshots plus incremental `btrfs send` to another disk/machine, i.e.
real backups (snapper snapshots live on the same disk).

## Garbage collection

`nix-gc.timer` (weekly, catches up after downtime): `nix-collect-garbage --delete-older-than 14d`; `nix-optimise.timer`
(weekly) hard-links identical store files.

## Commands

From NixOS:

    sudo nixos-rebuild switch

From Ubuntu (recovery only; reinstalls into @nixos and the ESP):

    sudo mkdir -p /mnt/nixos-persist
    sudo mount -o subvol=@persist UUID=b9218cc9-197b-4d2a-8013-3deee2e6147c /mnt/nixos-persist
    sudo /mnt/nixos-persist/etc/nixos/install-from-ubuntu.sh
