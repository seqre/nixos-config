# Acer-signed ADSP/CDSP/GPU-zap firmware, copied from the Windows DriverStore by qcom-firmware-extract on Ubuntu
# (/usr/lib/firmware/updates/qcom/x1e80100/ACER/SFG14-01). Not redistributable: keep blobs/ out of any public repo.
# Left uncompressed, as on Ubuntu, where these exact files are known to load.
# `src` is the flake input `acer-firmware` (/etc/nixos/blobs/firmware, git-ignored).
{ runCommand, src }:

runCommand "acer-sfg14-01-firmware"
  {
    passthru.compressFirmware = false;
  }
  ''
    mkdir -p $out/lib/firmware/qcom/x1e80100/ACER/SFG14-01
    cp ${src}/* $out/lib/firmware/qcom/x1e80100/ACER/SFG14-01/
  ''
