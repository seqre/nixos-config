{
  config,
  lib,
  pkgs,
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
    ./modules/sfg14-hardware.nix
    ./modules/camera.nix
    ./modules/fingerprint.nix
    ./modules/impermanence.nix
    ./modules/firmware-sync.nix
    ./modules/snapshots.nix
  ];

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
    };
    efi = {
      canTouchEfiVariables = false;
      efiSysMountPoint = "/boot";
    };
    timeout = 5;
  };

  secomet.impermanence = {
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
  swapDevices = [ { device = "/swap/swapfile"; } ];

  networking.hostName = "secomet";
  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };

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

  time.timeZone = "Europe/Warsaw";
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
  # Polish (programmer) layout system-wide: GDM, Xorg and, via useXkbConfig, the text console. GNOME keeps its own
  # per-user input sources (home/seqre.nix).
  services.xserver.xkb.layout = "pl";
  console.useXkbConfig = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
    ];
    hashedPasswordFile = "/persist/secrets/seqre.passwd";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.seqre = import ./home/seqre.nix;
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

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "seqre"
    ];
  };

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
  ];

  system.stateVersion = "26.11";
}
