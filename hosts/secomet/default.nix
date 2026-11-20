# Acer Swift Go 14 AI (SFG14-01, Snapdragon X x1p42100). Hardware support lives next to this file (hardware.nix,
# camera.nix, fingerprint.nix, firmware-sync.nix, pkgs/, files/).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  fsUuid = "b9218cc9-197b-4d2a-8013-3deee2e6147c"; # nvme0n1p5
  espUuid = "A48E-20FE"; # nvme0n1p1, shared with Windows
  btrfs = subvol: extra: {
    device = "/dev/disk/by-uuid/${fsUuid}";
    fsType = "btrfs";
    options = [
      "subvol=${subvol}"
      "compress=zstd:1"
      "noatime"
    ]
    ++ extra;
  };
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    inputs.eventually.nixosModules.default
    ./hardware.nix
    ./camera.nix
    ./fingerprint.nix
    ./firmware-sync.nix
    ../../modules/impermanence.nix
    ../../modules/snapshots.nix
    ../../modules/printing.nix
    ../../modules/nas.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # systemd-boot on the shared ESP (\EFI\systemd, kernels in \EFI\nixos, entries in \loader). NixOS never writes UEFI
  # variables: this firmware only boots entries carrying the `RC` optional data, so the "NixOS" UEFI entry was made
  # by hand (see README). `efi=noruntime` would block runtime variable writes from NixOS anyway.
  boot.loader = {
    systemd-boot = {
      enable = true;
      editor = false;
      configurationLimit = 10;
      # Loads the DTB from hardware.deviceTree (installDeviceTree defaults to on with deviceTree.name set).
      # Windows Boot Manager is detected automatically.

      # "built on" with the time, not just the date (the menu shows it after the title). The builder hardcodes %F
      # and takes it from the store path's ctime, which `nix-store --optimise` bumps; use the mtime of the
      # generation's profile link instead (when it was created). The builder leaves existing entry files alone
      # (named after a hash of their original contents), so this edits each one once.
      extraInstallCommands = ''
        for entry in ${config.boot.loader.efi.efiSysMountPoint}/loader/entries/nixos-*.conf; do
          gen=$(${pkgs.gnused}/bin/sed -n 's/^version Generation \([0-9]*\) .*/\1/p' "$entry")
          link=/nix/var/nix/profiles/system-$gen-link
          [ -n "$gen" ] && [ -L "$link" ] || continue
          built=$(${pkgs.coreutils}/bin/date -d "@$(${pkgs.coreutils}/bin/stat -c %Y "$link")" '+%F %H:%M')
          ${pkgs.gnused}/bin/sed -i "s/, built on [0-9-]*\( [0-9:]*\)\?$/, built on $built/" "$entry"
        done
      '';
    };
    efi = {
      canTouchEfiVariables = false;
      efiSysMountPoint = "/boot";
    };
    timeout = 5;
  };

  local.impermanence = {
    enable = true;
    inherit fsUuid;
  };

  # / (@nixos) is recreated empty on every boot (modules/impermanence.nix).
  fileSystems = {
    "/" = btrfs "@nixos" [ ];
    "/persist" = btrfs "@persist" [ ];
    "/nix" = btrfs "@nix" [ ];
    "/home" = btrfs "@home-nixos" [ ];
    "/boot" = {
      device = "/dev/disk/by-uuid/${espUuid}";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/swap" = (btrfs "@swap" [ ]) // {
      options = [
        "subvol=@swap"
        "noatime"
      ];
    };
    "/mnt/btrfs-top" = {
      device = "/dev/disk/by-uuid/${fsUuid}";
      fsType = "btrfs";
      options = [
        "subvolid=5"
        "noauto"
        "x-systemd.automount"
      ];
    };
  };
  # NixOS recreates the file with `btrfs filesystem mkswapfile` at boot whenever its size differs from `size` (MiB).
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 20 * 1024;
    }
  ];

  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];

  # Wi-Fi country PL. ath12k's firmware restarts on every resume in the world regdom (00), where all of 5 GHz is
  # passive-scan and all of 6 GHz is allowed: a full scan took 14.7 s (vs 4.8 s with PL), delaying the reconnect.
  # The sleep hook runs inside systemd-sleep, before NetworkManager hears about the wake-up and starts scanning.
  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=PL";
  environment.etc."systemd/system-sleep/wifi-regdom".source = pkgs.writeShellScript "wifi-regdom" ''
    [ "$1" = post ] || exit 0
    iw=${pkgs.iw}/bin/iw
    phy=$($iw reg get | ${pkgs.gnused}/bin/sed -n '/^phy#/{n;s/^country \([A-Z0-9]*\):.*/\1/p;q}')
    if [ "$phy" != PL ]; then
      # cfg80211 ignores a hint equal to the current one, so drop it first to reach the firmware again.
      $iw reg set 00
      $iw reg set PL
    fi
    echo "wifi-regdom: phy was ''${phy:-unknown}, now $($iw reg get | ${pkgs.gnused}/bin/sed -n '/^phy#/{n;p;q}')" \
      | ${pkgs.util-linux}/bin/logger -t wifi-regdom
  '';

  # English messages and sorting, Polish formats (dates, numbers, currency, units, paper size).
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = lib.genAttrs [
    "LC_TIME"
    "LC_NUMERIC"
    "LC_MONETARY"
    "LC_MEASUREMENT"
    "LC_PAPER"
    "LC_ADDRESS"
    "LC_TELEPHONE"
    "LC_NAME"
    "LC_IDENTIFICATION"
  ] (_: "pl_PL.UTF-8");
  # The Polish layout (modules/common.nix) on the text console too. GNOME keeps its own per-user input sources
  # (home/seqre.nix).
  console.useXkbConfig = true;

  # /etc/shadow does not survive a reboot, so users are fully declarative. The password hash lives in /persist
  # (root-only, copied from Ubuntu's /etc/shadow at install time), not in the Nix store.
  users.mutableUsers = false;
  users.users.seqre = {
    isNormalUser = true;
    uid = 1000;
    description = "seqre";
    extraGroups = [
      "wheel"
      "video"
      "networkmanager"
      "ydotool"
    ];
    hashedPasswordFile = "/persist/secrets/seqre.passwd";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.seqre = import ../../home/seqre.nix;
  };

  # Weekly GC of store paths not referenced by a generation from the last 14 days (old systemd-boot entries go with
  # them on the next rebuild).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true; # catch up after the laptop was off at the scheduled time
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true; # weekly hard-link dedup of identical store files

  services.eventually = {
    enable = true;
    port = 2137;
    secretKeyFile = "/home/seqre/.eventually/secret-key";
    admin = {
      username = "admin";
      passwordFile = "/home/seqre/.eventually/admin-password";
    };
  };
  # The database lives in /var/lib/eventually (the service can't reach /home: ProtectHome, DynamicUser). With
  # DynamicUser that is a symlink to /var/lib/private/eventually, so persist the real directory.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/private";
      mode = "0700";
    }
    # The whole directory: tailscaled replaces tailscaled.state via temp file + rename, which a persisted single file
    # (bind mount or symlink) can't take.
    {
      directory = "/var/lib/tailscale";
      mode = "0700";
    }
  ];

  # This flake is /etc/nixos (persisted in /persist/etc/nixos, owned by root): edit with sudo, apply with
  # `sudo nixos-rebuild switch` (builds nixosConfigurations.secomet = the hostname). safe.directory lets other users
  # run read-only git commands (log, diff, status) in the root-owned repo.
  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };

  # Except seqre's Home Manager config (~/.configuration.nix links here), which seqre edits without sudo. The directory
  # is seqre's too, so editors that save via a temp file and rename work. Applying it still needs sudo. Recursive `Z`
  # rather than one `z` per path: tmpfiles refuses a root-owned path under a seqre-owned directory ("unsafe path
  # transition"), which is what a file freshly written there by root (e.g. a git checkout) looks like.
  systemd.tmpfiles.rules = [ "Z /etc/nixos/home - seqre users -" ];

  # ydotoold + ydotool for members of the ydotool group. Handy types its transcriptions through it. Don't install wtype:
  # it doesn't work on GNOME, but Handy would still pick it first.
  programs.ydotool.enable = true;

  # Default editor for everyone (EDITOR=nvim, so also root and sudoedit); this also installs neovim.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  # Only these unfree packages (Home Manager uses the system nixpkgs: useGlobalPkgs).
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  environment.systemPackages = with pkgs; [
    git
    vim
    ranger
    fastfetch
    pciutils
    usbutils
    dtc
    i2c-tools
    libgpiod
    v4l-utils
    evtest
    btrfs-progs
    efibootmgr
    python3
  ];

  system.stateVersion = "26.11";
}
