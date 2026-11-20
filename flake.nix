{
  description = "NixOS for seqre's laptops: secomet (Acer Swift Go 14 AI, Snapdragon X) and secorbit (x86_64, NVIDIA)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    # secomet only. Acer's firmware (not redistributable) is git-ignored, so it can't come in through `self`. A path
    # input reads it from disk, pinned by hash in flake.lock: after changing the files, `sudo nix flake update
    # acer-firmware` (qcom-firmware-sync does this itself).
    acer-firmware = {
      url = "path:/etc/nixos/blobs/firmware";
      flake = false;
    };
    # secomet only; a local checkout on that machine.
    eventually.url = "git+file:///home/seqre/dev/eventually?ref=main";
  };

  # Inputs are fetched only when used, so a host that doesn't use acer-firmware or eventually builds on a machine that
  # doesn't have them.
  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Every directory in hosts/ is a host: hosts/<name>/default.nix sets its own platform (nixpkgs.hostPlatform)
      # and imports the input modules and modules/ it uses. Modules get `inputs` and `self` as arguments.
      mkHost =
        name:
        lib.nixosSystem {
          specialArgs = { inherit inputs self; };
          modules = [
            ./modules/common.nix
            ./hosts/${name}
            { networking.hostName = name; }
          ];
        };
      hosts = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));
    in
    {
      # `sudo nixos-rebuild switch` picks the one named after the hostname.
      nixosConfigurations = lib.genAttrs hosts mkHost;

      # secomet's hardware packages, buildable on their own, e.g. `nix build .#kernel`.
      packages.aarch64-linux =
        let
          inherit (self.nixosConfigurations.secomet) pkgs;
          kernel = pkgs.callPackage ./hosts/secomet/pkgs/kernel { };
        in
        {
          inherit kernel;
          dtbs = pkgs.callPackage ./hosts/secomet/pkgs/dtb { inherit kernel; };
          ov05c10 = pkgs.callPackage ./hosts/secomet/pkgs/ov05c10 { inherit kernel; };
          acer-firmware = pkgs.callPackage ./hosts/secomet/pkgs/acer-firmware.nix { src = inputs.acer-firmware; };
          toplevel = self.nixosConfigurations.secomet.config.system.build.toplevel;
        };
    };
}
