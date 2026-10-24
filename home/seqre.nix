# Home Manager for seqre. /home is persistent (@home-nixos), so this only manages dotfiles; it is a starting point.
{ config, lib, pkgs, ... }:

{
  home.username = "seqre";
  home.homeDirectory = "/home/seqre";

  programs.bash.enable = true;
  programs.git.enable = true;

  # Claude Code (unfree; allowed for this package only in configuration.nix). No `settings` here, so ~/.claude stays
  # writable by Claude Code itself.
  programs.claude-code.enable = true;

  # No profiles declared, so the existing ~/.mozilla profile is left alone.
  programs.firefox = {
    enable = true;
    # The built-in camera only works through PipeWire/libcamera; Firefox's direct V4L2 path would open the raw
    # CAMSS nodes (no image processing). Ubuntu set this in the snap's user.js; a policy default works for any profile.
    policies.Preferences."media.webrtc.camera.allow-pipewire" = {
      Value = true;
      Status = "default";
    };
  };

  # ~/.configuration.nix -> this file in the system flake (a live link, not a store copy). This file is owned by
  # seqre (systemd.tmpfiles in secomet.nix), so edit it directly; apply with `sudo nixos-rebuild switch`.
  home.file.".configuration.nix".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/home/seqre.nix";

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };

  dconf.settings."org/gnome/desktop/input-sources" = {
    sources = [ (lib.hm.gvariant.mkTuple [ "xkb" "pl" ]) ];
    xkb-options = [ "terminate:ctrl_alt_bksp" ];
  };

  # GNOME Settings → Region → Formats. Overrides the LC_* variables inside the GNOME session, so keep it in step with
  # i18n.extraLocaleSettings in secomet.nix.
  dconf.settings."org/gnome/system/locale".region = "pl_PL.UTF-8";

  # Personal scripts, e.g. lost-on-boot (what on the ephemeral root would be lost on reboot).
  home.sessionPath = [ "$HOME/.local/bin" ];

  home.packages = with pkgs; [
    signal-desktop
    zed-editor
    htop
    ripgrep
    fd
    jq
    gh
    gimp
    inkscape
    libreoffice
    # Anki breaks under XWayland; force its native Wayland backend (binary and desktop entry both resolve to this wrapper).
    (symlinkJoin {
      name = "anki-wayland";
      paths = [ anki ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = "wrapProgram $out/bin/anki --set ANKI_WAYLAND 1";
    })
    just
    fzf
    ripgrep
    opencode
    jujutsu
  ];

  home.stateVersion = "26.11";
}
