# The jg kernel (Jens Glathe's Snapdragon X tree), the same 7.2.2-jg-0 source Ubuntu runs.
# `config` is Ubuntu's /boot/config-7.2.2-jg-0-qcom-x1e after `olddefconfig` with:
#   LOCALVERSION="-jg-0-nixos", SECURITY_LOCKDOWN_LSM off (it forces MODULE_SIG on),
#   MODULE_SIG off, IMA_APPRAISE_MODSIG off, SYSTEM_REVOCATION_LIST off,
#   UBSAN off: nixpkgs builds from the source unpacked in $dev, and GCC applies no prefix map to the file names
#   UBSAN embeds, so Image and modules would reference $dev ("cycle detected ... output 'dev' from output 'out'",
#   +900 MB closure), and the initrd's nuke-refs then corrupts the zstd modules that contain the path as literal
#   bytes (raid6_pq, hence btrfs: root never ready).
# Nothing else differs, so drivers and DT behave as on Ubuntu.
{
  fetchFromGitHub,
  linuxManualConfig,
  ...
}:

linuxManualConfig {
  version = "7.2.2-jg-0";
  modDirVersion = "7.2.2-jg-0-nixos";

  src = fetchFromGitHub {
    owner = "jglathe";
    repo = "linux_ms_dev_kit";
    rev = "jg/ubuntu-qcom-x1e-7.2.2-jg-0";
    hash = "sha256-e62tbrVGmdB8nAENVOZIvYj+78ZeJWJ7rwu/rhdeK64=";
  };

  configfile = ./config;

  # Passthru only (no rebuild). CONFIG_EFI_STUB=y; the systemd-boot module checks this attribute, which nixpkgs'
  # generic kernels declare but a manual config doesn't.
  features.efiBootStub = true;

  kernelPatches = [
    {
      # ~/acer-swift-retimer-fix: PS8830 reset is active-low (dock USB 3 + DP alt mode).
      name = "dts-acer-swift-14-retimer-reset-polarity";
      patch = ./0001-dts-acer-swift-14-retimer-reset-polarity.patch;
    }
    {
      # /usr/local/src/camss-x1p: qcom,x1p42100-camss (no VFE1, CSIPHY0/4 only).
      name = "media-camss-add-x1p42100-purwa";
      patch = ./0002-media-camss-add-x1p42100-purwa.patch;
    }
  ];
}
