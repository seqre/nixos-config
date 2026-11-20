# Built-in OV05C10 camera userspace (see ~/ISSUES.md, "Built-in camera"). The kernel side (CAMSS patch, ov05c10
# module, DT overlay, cma=256M) is in sfg14-hardware.nix.
#
# libcamera: nixpkgs' 0.7.2 already has all 38 upstream soft-ISP commits Ubuntu had to backport, and the Vector
# helpers. Only the local radial lens shading correction is added (`Lsc` IPA algorithm + GPU ISP shader; the GPU ISP
# is on in nixpkgs). Source: /usr/local/src/libcamera branch softisp-local on Ubuntu, commit 990a193fd, minus the
# build.log/.wraplock files it accidentally contained, ported to 0.7.2's tuning API (YamlObject -> ValueNode,
# getList<float>() -> get<std::vector<float>>()).
#
# Only the processes that run the camera get it, so nothing else is rebuilt: the PipeWire daemon (SPA libcamera
# plugin), WirePlumber (libcamera monitor, built against that PipeWire) and the `cam` tool. Apps reach the camera
# through PipeWire. A global overlay would rebuild everything that links PipeWire (GNOME Shell, Firefox, ...).
#
# Tuning file: files/ov05c10.yaml = Ubuntu's /etc/libcamera/ipa/simple/ov05c10.yaml (black level 64@10 bit, CCMs from
# the Windows tuning at 70%, Lsc from a flat-field calibration at strength 0.8). Its `Lsc` block needs this libcamera;
# a stock libcamera refuses to start the camera with it.
{ pkgs, ... }:

let
  libcamera = pkgs.libcamera.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./pkgs/libcamera/0001-softisp-radial-lens-shading-correction.patch ];
  });
  pipewire = pkgs.pipewire.override { inherit libcamera; };
  wireplumber = pkgs.wireplumber.override { inherit pipewire; };
in
{
  services.pipewire = {
    enable = true;
    package = pipewire;
    wireplumber.package = wireplumber;
  };

  environment.systemPackages = [ libcamera ]; # cam, libcamerify

  environment.etc."libcamera/ipa/simple/ov05c10.yaml".source = ./files/ov05c10.yaml;

  # nixpkgs' libcamera looks for tuning files in its own store path only. sessionVariables also reach the systemd
  # user manager (PAM), so PipeWire and WirePlumber see it too.
  environment.sessionVariables.LIBCAMERA_IPA_CONFIG_PATH = "/etc/libcamera/ipa";
}
