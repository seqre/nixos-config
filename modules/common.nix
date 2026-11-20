# Settings shared by every host. Imported for all hosts by mkHost in flake.nix, which also sets networking.hostName
# from the host's directory name (hosts/<name>).
{ ... }:

{
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

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Warsaw";
  services.xserver.xkb.layout = "pl";

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.tailscale.enable = true;
}
