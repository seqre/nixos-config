# nixos-secomet

NixOS for the Acer Swift Go 14 AI (SFG14-01, Snapdragon X x1p42100), on btrfs (`nvme0n1p5`) with the ESP
(`nvme0n1p1`, grown to 2.2 GB) shared with Windows. It was first installed next to Ubuntu, where the hardware was
brought up; Ubuntu was removed afterwards (`~/installation-docs/UBUNTU-REMOVAL.md`). The hardware fixes are the ones
documented in `~/installation-docs/ISSUES.md`; each file says which section it comes from.

This repo is **`/etc/nixos`** on NixOS: persisted in `@persist` (`/persist/etc/nixos`, bind-mounted by impermanence),
owned by root. Edit with sudo, apply with `sudo nixos-rebuild switch`.

**Not for a public repo:** `blobs/firmware/` holds Acer's firmware, copied from Windows. It is git-ignored and enters
the build as the flake input `acer-firmware` (`path:/etc/nixos/blobs/firmware`, pinned by hash in `flake.lock`).
After changing those files by hand, run `sudo nix flake update acer-firmware`, or the build fails with a hash mismatch.

## Layout on disk

| Subvolume                 | Mounted at          |
|---------------------------|---------------------|
| `@nix`                    | `/nix`              |
| `@nixos`                  | `/`, **recreated empty on every boot** |
| `@nixos-old/<timestamp>`  | (not mounted) previous roots, deleted after 14 days |
| `@persist`                | `/persist`: the state that survives, including this repo (`/etc/nixos`) |
| `@home-nixos`             | `/home` (persistent; dotfiles via Home Manager) |
| `@swap`                   | `/swap` (swapfile)  |

`/mnt/btrfs-top` (automount) is the btrfs top level, for looking at `@nixos-old/`.

NixOS generations are the rollback mechanism for the system; snapper covers `/home` and `/persist` (see Snapshots).
`nix-collect-garbage -d` deletes all old NixOS generations.

## Impermanence

- The initrd unit `rollback-root` moves `@nixos` to `@nixos-old/<mtime>` and creates an empty `@nixos` before
  `/sysroot` is mounted.
- `environment.persistence."/persist"` bind-mounts: `/etc/nixos` (root:root 0755), `/var/log`, `/var/lib/{nixos,systemd,bluetooth,fprint,
  NetworkManager,AccountsService,gdm,colord,upower,power-profiles-daemon,udisks2}`,
  `/etc/NetworkManager/system-connections`, `/etc/machine-id`.
- Users are declarative (`users.mutableUsers = false`). `seqre`'s password hash is in `/persist/secrets/seqre.passwd`
  (root-only; originally copied from Ubuntu's `/etc/shadow`). To change it: `mkpasswd -m yescrypt` and write the hash there.
- Anything else written outside `/home`, `/nix` and `/persist` is gone after a reboot. To keep something, add it to
  `modules/impermanence.nix`, move the current copy into `/persist/...`, rebuild.
- Before shutting down, run **`lost-on-boot`** (`~seqre/.local/bin/lost-on-boot`, re-runs itself with sudo) to see what is on
  the root right now and would be lost. It reads the raw `@nixos` through `/mnt/btrfs-top` and hides what activation
  recreates anyway. `-t` adds tmp and caches, `-s` gives per-directory counts, `-n` prints a persistence snippet,
  `-a` turns off all filtering. Extra ignore globs: `~/.config/lost-on-boot/ignore`.

## Boot path

1. UEFI **`Boot0003` "NixOS (systemd-boot)"** → `\EFI\systemd\systemd-bootaa64.efi`. Created by hand with the `RC`
   optional data this firmware requires:
   `printf RC > rc.bin; efibootmgr -c -d /dev/nvme0n1 -p 1 -L "NixOS (systemd-boot)" -l '\EFI\systemd\systemd-bootaa64.efi' -@ rc.bin`
   NixOS never writes UEFI variables (`canTouchEfiVariables = false`). **Boot order:** this is Insyde firmware, which
   rebuilds `BootOrder` from its own setup list at every power-on (new entries go last). Set it in the firmware setup
   (F2 → Boot → Boot priority order); `efibootmgr -n 0003` works for one boot.
2. systemd-boot menu: NixOS generations (kernel, initrd and DTB copied to `\EFI\nixos`), Windows Boot Manager
   (auto-detected).
3. Fallback: `\EFI\BOOT\BOOTAA64.EFI` is systemd-boot too (installed by `bootctl`). The ESP as it was before
   systemd-boot is in `~/ubuntu-backup/backups/esp-before-systemd-boot-2026-10-03.tar`.
4. The `cutmem` workaround Ubuntu's GRUB applied is not needed: RAM on this 16 GB model ends at `0xbffffffff`,
   below the cut range.

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
- `modules/printing.nix`: CUPS + ipp-usb (IPP over USB), with a declared PostScript queue for the HP M553 (it drops PDF
  jobs); the PPD comes from hplip, but hplip itself is not installed.
- `modules/firmware-sync.nix`, `modules/snapshots.nix`: see below.
- `secomet.nix`: the host config: boot loader, filesystems, GNOME, users, Home Manager, Nix GC.
- `home/seqre.nix`: Home Manager config for seqre, linked as `~/.configuration.nix`; owned by seqre (editable without sudo), applying still needs sudo.

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

    sudo nixos-rebuild switch

Recovery: pick an older generation in the systemd-boot menu. The old `install-from-ubuntu.sh` (installs this flake
into `@nixos` from another Linux on the same disk) is in git history.
