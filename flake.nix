{
  description = "NixOS for secomet (Acer Swift Go 14 AI SFG14-01, Snapdragon X x1p42100)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    # Acer's firmware (not redistributable) is git-ignored, so it can't come in through `self`. A path input reads it
    # from disk, pinned by hash in flake.lock: after changing the files, `sudo nix flake update acer-firmware`
    # (qcom-firmware-sync does this itself).
    acer-firmware = {
      url = "path:/etc/nixos/blobs/firmware";
      flake = false;
    };
    eventually.url = "git+file:///home/seqre/dev/eventually?ref=main";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      impermanence,
      acer-firmware,
      eventually,
    }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      kernel = pkgs.callPackage ./pkgs/kernel { };
    in
    {
      nixosConfigurations.secomet = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit self acer-firmware; };
        modules = [
          { nixpkgs.hostPlatform = system; }
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
	  eventually.nixosModules.default
          ./secomet.nix
        ];
      };

      # Buildable on their own, e.g. `nix build .#kernel`.
      packages.${system} = {
        inherit kernel;
        dtbs = pkgs.callPackage ./pkgs/dtb { inherit kernel; };
        ov05c10 = pkgs.callPackage ./pkgs/ov05c10 { inherit kernel; };
        acer-firmware = pkgs.callPackage ./pkgs/acer-firmware.nix { src = acer-firmware; };
        toplevel = self.nixosConfigurations.secomet.config.system.build.toplevel;
      };
    };
}
