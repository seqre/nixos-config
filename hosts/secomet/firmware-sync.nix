# Keep the Acer DSP/GPU firmware (blobs/firmware) in sync with Windows, like qcom-firmware-extract +
# qcom-firmware-sync did on Ubuntu (see ~/ISSUES.md, "Battery" → "Kept up to date").
#
# A daily timer mounts the Windows partition read-only, takes the newest copy of each file
# in the DriverStore (the same file list and pick as qcom-firmware-extract 21) and compares it with blobs/firmware.
# If anything changed:
#   1. the new files go into /etc/nixos/blobs/firmware (git-ignored, the flake input `acer-firmware`) and the input is
#      re-locked (`nix flake update acer-firmware`), so future rebuilds have them;
#   2. `nixos-rebuild boot` builds the *current default generation's* flake source (recorded in every generation as
#      `flake-source`) with only the firmware input swapped (`--override-input`). Uncommitted work in /etc/nixos never ends up in an automatic
#      build. The new firmware is used from the next boot on.
# Windows updates the firmware through Windows Update, so boot Windows now and then.
# Logs: journalctl -u qcom-firmware-sync. By hand: sudo systemctl start qcom-firmware-sync.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:

let
  # qcom-firmware-extract 21's list (covers X1E/X1P and X2; only files Windows has are used).
  fwFiles = [
    "adsp_dtbs.elf"
    "adspr.jsn"
    "adsps.jsn"
    "adspua.jsn"
    "battmgr.jsn"
    "cdsp_dtbs.elf"
    "cdspr.jsn"
    "qcadsp8380.mbn"
    "qccdsp8380.mbn"
    "qcadsp8480.mbn"
    "qccdsp8480.mbn"
    "qcdxkmsuc8380.mbn"
    "qcdxkmsucpurwa.mbn"
    "soccp.mbn"
    "soccp_dtb.mbn"
  ];

  sync = pkgs.writeShellApplication {
    name = "qcom-firmware-sync";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      diffutils
      util-linux
      ntfs3g
      git
      config.system.build.nixos-rebuild
      config.nix.package
    ];
    text = ''
      FLAKE=/etc/nixos
      BLOBS=$FLAKE/blobs/firmware
      DRIVERSTORE=Windows/System32/DriverStore/FileRepository
      log() { echo "qcom-firmware-sync: $*"; }

      if blkid -t TYPE=BitLocker -o device | grep -q .; then
        log "a BitLocker volume is present; only plain NTFS is supported. Copy new firmware into $BLOBS by hand."
        exit 1
      fi

      mnt=$(mktemp -d /run/qcom-firmware-sync.XXXXXX)
      work=""
      cleanup() {
        umount -q "$mnt" 2>/dev/null || true
        rmdir "$mnt"
        [ -z "$work" ] || rm -rf "$work"
      }
      trap cleanup EXIT

      found=""
      for dev in $(blkid -t TYPE=ntfs -o device); do
        ntfs-3g -o ro "$dev" "$mnt" 2>/dev/null || continue
        if [ -d "$mnt/$DRIVERSTORE" ]; then found=$dev; break; fi
        umount "$mnt"
      done
      [ -n "$found" ] || { log "no NTFS partition with a Windows DriverStore found"; exit 1; }

      new=$(mktemp -d /run/qcom-firmware-sync-new.XXXXXX)
      changed=()
      for f in ${lib.escapeShellArgs fwFiles}; do
        # Same pick as qcom-firmware-extract: newest copy anywhere in the DriverStore.
        win=$(find "$mnt/$DRIVERSTORE" -name "$f" -exec ls -t {} + | head -n1)
        [ -n "$win" ] || continue
        if ! cmp -s "$win" "$BLOBS/$f"; then
          cp --preserve=timestamps "$win" "$new/$f"
          changed+=("$f")
        fi
      done
      umount "$mnt"

      if [ ''${#changed[@]} -eq 0 ]; then
        log "blobs/firmware matches Windows ($found), nothing to do"
        rm -rf "$new"
        exit 0
      fi
      log "changed in Windows ($found): ''${changed[*]}"

      # 1. Into the repo.
      for f in "''${changed[@]}"; do install -m 644 "$new/$f" "$BLOBS/$f"; done
      nix flake update acer-firmware --flake "$FLAKE" ||
        log "warning: re-locking failed; run 'sudo nix flake update acer-firmware' in $FLAKE by hand"

      # 2. Rebuild the current default generation with only the firmware swapped.
      src=$(readlink -f /nix/var/nix/profiles/system/flake-source || true)
      if [ ! -d "$src" ]; then
        log "current generation has no flake-source; run 'sudo nixos-rebuild boot' to use the new firmware"
        exit 0
      fi
      work=$(mktemp -d /var/tmp/qcom-firmware-sync-flake.XXXXXX)
      cp -r --no-preserve=mode,ownership "$src"/. "$work"/
      rm -rf "$new"
      nixos-rebuild boot --flake "path:$work#secomet" --override-input acer-firmware "path:$BLOBS"
      log "new firmware installed for the next boot"
    '';
  };
in
{
  # Every generation records the flake source it was built from (also handy for diffing generations).
  system.systemBuilderCommands = "ln -s ${self} $out/flake-source";

  environment.systemPackages = [ sync ];

  systemd.services.qcom-firmware-sync = {
    description = "Sync Acer Qualcomm firmware from the Windows DriverStore into /etc/nixos";
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe sync;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.qcom-firmware-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true; # if the laptop was off at midnight, run at the next boot instead
      RandomizedDelaySec = "1h";
    };
  };
}
