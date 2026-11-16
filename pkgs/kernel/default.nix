# The jg kernel (Jens Glathe's Snapdragon X tree), branch jg/ubuntu-qcom-x1e-7.3.y (7.3.3-jg-1 per its changelog).
# `config` is the tree's Ubuntu qcom-x1e flavour, exported with
#   `debian/scripts/misc/annotations -f debian.qcom-x1e/config/annotations --arch arm64 --flavour qcom-x1e --export`
# then `olddefconfig` (with pahole in PATH, as in the nixpkgs build, or BTF gets dropped) with:
#   LOCALVERSION="-jg-1-nixos", SECURITY_LOCKDOWN_LSM off (it forces MODULE_SIG on; not in LSM either),
#   MODULE_COMPRESS_ALL on (Ubuntu compresses modules in its packaging, nixpkgs relies on modules_install),
#   boot-path platform drivers built in where Ubuntu has =m (GCC, X1E pinctrl, interconnect, RPMh regulators, SPMI,
#   SMEM, QMP PHYs, DWC3, Type-C, ...): Ubuntu's dracut initramfs loads them all, the hand-picked initrd here doesn't,
#   CPU_FREQ_DEFAULT_GOV_SCHEDUTIL (Ubuntu: ondemand),
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
  version = "7.3.3-jg-1";
  modDirVersion = "7.3.3-jg-1-nixos";

  src = fetchFromGitHub {
    owner = "jglathe";
    repo = "linux_ms_dev_kit";
    rev = "27cbafd8ed14e940260f6b7963ce46e61234cf89"; # jg/ubuntu-qcom-x1e-7.3.y, 2026-11-15
    hash = "sha256-sRVGgVH1hBpsWjmf4gerUl9HCV22lQ216H/Hq+LSNqA=";
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
    {
      # ~/installation-docs/ISSUES.md "Suspend drain", step 4a: the PDC can't detect both edges, so without the
      # errata flag the lid GPIO only reports rising edges and closing the lid never suspends.
      name = "pinctrl-qcom-x1e80100-dual-edge-errata";
      patch = ./0003-pinctrl-qcom-x1e80100-dual-edge-errata.patch;
    }
    {
      # The eDP bpp is picked from the link caps, which must be read first, or the panel runs at 6 bpc (banding).
      name = "drm-msm-dp-read-edp-link-caps-before-setting-mode";
      patch = ./0004-drm-msm-dp-read-edp-link-caps-before-setting-mode.patch;
    }
  ];
}
