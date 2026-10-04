# Ephemeral root ("erase your darlings") on btrfs.
#
# Every boot, before / is mounted, the initrd moves the previous root subvolume @nixos to @nixos-old/<timestamp> and
# creates an empty @nixos. Old roots are kept 14 days for recovery (mount the btrfs top level and look in
# @nixos-old/). NixOS rebuilds /etc, /bin/sh etc. on activation; everything else that must survive is listed below
# and lives in @persist (/persist), bind-mounted into place by the impermanence module.
# /nix (@nix) and /home (@home-nixos) are separate persistent subvolumes and not affected.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.secomet.impermanence;
  device = "/dev/disk/by-uuid/${cfg.fsUuid}";
  deviceUnit = "dev-disk-by\\x2duuid-${lib.replaceStrings [ "-" ] [ "\\x2d" ] cfg.fsUuid}.device";
in
{
  options.secomet.impermanence = {
    enable = lib.mkEnableOption "ephemeral btrfs root with state in /persist";
    fsUuid = lib.mkOption { type = lib.types.str; };
    rootSubvol = lib.mkOption {
      type = lib.types.str;
      default = "@nixos";
    };
    keepDays = lib.mkOption {
      type = lib.types.int;
      default = 14;
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.systemd.initrdBin = [ pkgs.findutils ];

    boot.initrd.systemd.services.rollback-root = {
      description = "Move the previous root subvolume aside and create an empty one";
      wantedBy = [ "initrd.target" ];
      requires = [ deviceUnit ];
      after = [ deviceUnit ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        top=/rollback-btrfs-top
        mkdir -p $top
        mount -t btrfs -o subvolid=5 ${device} $top

        delete_recursively() {
          local sub
          btrfs subvolume list -o "$1" | cut -d ' ' -f 9- | while read -r sub; do
            delete_recursively "$top/$sub"
          done
          btrfs subvolume delete "$1"
        }

        if [ -e "$top/${cfg.rootSubvol}" ]; then
          mkdir -p "$top/${cfg.rootSubvol}-old"
          ts=$(date --date="@$(stat -c %Y "$top/${cfg.rootSubvol}")" '+%Y-%m-%d_%H-%M-%S')
          [ -e "$top/${cfg.rootSubvol}-old/$ts" ] && ts="$ts-$$"
          mv "$top/${cfg.rootSubvol}" "$top/${cfg.rootSubvol}-old/$ts"
        fi

        find "$top/${cfg.rootSubvol}-old" -mindepth 1 -maxdepth 1 -mtime +${toString cfg.keepDays} 2>/dev/null |
          while read -r old; do delete_recursively "$old" || true; done

        btrfs subvolume create "$top/${cfg.rootSubvol}"
        umount $top
      '';
    };

    fileSystems."/persist".neededForBoot = true;

    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        {
          # This flake. Root-owned on purpose: changing the system config needs sudo.
          directory = "/etc/nixos";
          user = "root";
          group = "root";
          mode = "0755";
        }
        "/var/log"
        "/var/lib/nixos" # uid/gid allocations: keeps ownership in /home stable
        "/var/lib/systemd" # timers, rfkill and backlight state, random seed, coredumps
        "/var/lib/bluetooth"
        "/var/lib/fprint" # fprintd's record of prints stored on the sensor
        "/var/lib/NetworkManager"
        {
          directory = "/etc/NetworkManager/system-connections";
          mode = "0700";
        }
        "/var/lib/AccountsService"
        "/var/lib/gdm"
        "/var/lib/colord"
        "/var/lib/upower"
        "/var/lib/power-profiles-daemon"
        "/var/lib/udisks2"
      ];
      files = [ "/etc/machine-id" ];
      # Claude Code run via sudo keeps its login and settings in root's home.
      users.root = {
        directories = [
          {
            directory = ".claude";
            mode = "0700";
          }
        ];
        files = [ ".claude.json" ];
      };
    };

    # /var/db/sudo/lectured is gone every boot.
    security.sudo.extraConfig = "Defaults lecture=never";
  };
}
