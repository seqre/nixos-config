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

  installPhase = ''
    install -Dm644 ov05c10.ko $out/lib/modules/${kernel.modDirVersion}/updates/ov05c10.ko
  '';
}
