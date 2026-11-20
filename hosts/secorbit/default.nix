# x86_64 laptop with NVIDIA. Migrated from its standalone /etc/nixos. Hardware support is in hardware.nix.
{ config, lib, pkgs, inputs, ... }:

let
  fsUuid = "1703200f-ae06-4873-99ba-fa6da8e71d69"; # nvme0n1p2
  espUuid = "9F50-30DC";
  btrfs = subvol: extra: {
    device = "/dev/disk/by-uuid/${fsUuid}";
    fsType = "btrfs";
    options = [ "subvol=${subvol}" ];
  } // extra;
in
{
  imports =
    [
      inputs.impermanence.nixosModules.impermanence
      ./hardware.nix
      ../../modules/nas.nix
    ];

  nixpkgs.hostPlatform = "x86_64-linux";

  fileSystems = {
    "/" = btrfs "@" { };
    "/nix" = btrfs "@nix" { neededForBoot = true; };
    "/home" = btrfs "@home" { };
    "/persist" = btrfs "@persist" { neededForBoot = true; };
    # btrfs top level (@, @-clean snapshot, ...).
    "/.btrfs-root" = {
      device = "/dev/disk/by-uuid/${fsUuid}";
      fsType = "btrfs";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/${espUuid}";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
  };

  nix.settings = {
    flake-registry = "";
  };


  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 15d";
  };

  nixpkgs.config.allowUnfree = true;

  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root to blank";
    wantedBy = [ "initrd.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      mount -t btrfs -o subvol=/ /dev/disk/by-uuid/${fsUuid} /mnt
      btrfs subvolume delete /mnt/@
      btrfs subvolume snapshot /mnt/snapshots/@-clean /mnt/@
      umount /mnt
    '';
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/ssh"
      "/etc/NetworkManager/system-connections"
      "/var/log"
      "/var/lib/cups"
      "/var/lib/fprint"
      "/var/lib/docker"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/var/db/sudo/lectured"
    ];
    files = [
      "/etc/machine-id"
      { file = "/etc/nix/id_rsa"; parentDirectory = { mode = "0755"; }; }
      "/var/lib/logrotate.status"
    ];
  };

  # GNOME itself is enabled in modules/common.nix.
  services.gnome.core-apps.enable = true;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;

  services.printing.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  services.smartd = {
    enable = true;
    autodetect = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Password hashes live in /persist (root-only), not in the Nix store or this public repo.
  users.users.root.hashedPasswordFile = "/persist/secrets/root.passwd";
  users.users.seqre = {
    isNormalUser = true;
    createHome = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.fish;
    packages = with pkgs; [
      discord
      claude-code
      rustup
      gh
      anki
      helix
      wl-clipboard
      just
      libreoffice-fresh
      gimp
      zed-editor
      opencode
      signal-desktop
      unityhub
    ];
    hashedPasswordFile = "/persist/secrets/seqre.passwd";
  };

  programs.fish.enable = true;
  programs.firefox.enable = true;
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  virtualisation.docker.enable = true;
  virtualisation.docker.storageDriver = "btrfs";

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    neovim
    ranger
    wget
    curl
    tree
    git
    gnome-terminal
    jq
    smartmontools
    intel-media-driver
    waypipe
  ];

  environment.variables = {
    EDITOR = "nvim";
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  programs.mosh.enable = true;   # mosh otwiera UDP 60000-61000 globalnie, przenieś to na tailscale0:
  networking.firewall.allowedUDPPortRanges = lib.mkForce [ ];

  services.logind.lidSwitch = "ignore";
  services.logind.lidSwitchExternalPower = "ignore";
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = true;

  services.sunshine = { enable = false; autoStart = true; capSysAdmin = true; openFirewall = false; };
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 22 47984 47989 47990 48010 ];
    allowedUDPPortRanges = [ { from = 47998; to = 48000; } { from = 60000; to = 61000; } ];
  };

  #networking.firewall.enable = false;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}

