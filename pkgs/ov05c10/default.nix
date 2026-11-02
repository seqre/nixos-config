# OmniVision OV05C10 sensor driver: AMD's v4 + the Qualcomm/Acer fixes from
# /usr/local/src/ov05c10 (OF match, power-on order, gain/page/Bayer/flip fixes, lens-centred crop modes).
{ stdenv, kernel }:

stdenv.mkDerivation {
  pname = "ov05c10";
  version = "secomet-${kernel.modDirVersion}";
  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags = kernel.commonMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
  ];
  buildFlags = [ "modules" ];

  # The kernel's modules_install, not a plain copy: nixpkgs' commonMakeFlags hook kmodigest into it, which writes the
  # ov05c10.ko.cer that the module aggregation merges into modules.cer (and the module gets zstd-compressed like the
  # in-tree ones).
  installFlags = [
    "INSTALL_MOD_PATH=${placeholder "out"}"
    "INSTALL_MOD_DIR=updates"
  ];
  installTargets = [ "modules_install" ];
}
