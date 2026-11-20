# EgisTec 1c7a:0584 fingerprint reader (see ~/ISSUES.md, "Fingerprint"). The USB controller it sits on is enabled by
# the fingerprint DT overlay. This firmware only stores prints after an SDCP handshake, which needs libfprint
# MR !547 ("Implement SDCP v2 (including egismoc implementation)"), commit 2d7c5277: the same one Ubuntu runs.
{ pkgs, ... }:

let
  libfprint-sdcp = pkgs.libfprint.overrideAttrs (old: {
    version = "1.94.100-sdcp-2d7c5277";
    src = pkgs.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "libfprint";
      repo = "libfprint";
      rev = "2d7c5277de08c6b29b3fac7447f17a516fbc4d1c";
      hash = "sha256-sCUp5u2mZJts/5jE75e1uAYAHJWtf6fZoZu4yGW8/R0=";
    };
    # The MR's virtual-sdcp tests need gnome-desktop-testing-runner/umockdev; checked on Ubuntu instead.
    # meson still runs tests/unittest_inspector.py at configure time, which needs Python with PyGObject.
    doInstallCheck = false;
    nativeBuildInputs = old.nativeBuildInputs ++ old.nativeInstallCheckInputs;
  });
in
{
  services.fprintd = {
    enable = true;
    package = pkgs.fprintd.override { libfprint = libfprint-sdcp; };
  };
  # services.fprintd.enable turns on pam_fprintd for login, sudo, polkit and GDM (fprintAuth defaults to it).
}
