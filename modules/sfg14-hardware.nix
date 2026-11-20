# Acer Swift Go 14 AI (SFG14-01, Snapdragon X x1p42100): everything Ubuntu needed, see ~/ISSUES.md.
{
  config,
  lib,
  pkgs,
  acer-firmware,
  ...
}:

let
  kernel = pkgs.callPackage ../pkgs/kernel { };
  kernelPackages = pkgs.linuxPackagesFor kernel;
  acer-ec = pkgs.callPackage ../pkgs/acer-ec { };
in
{
  boot.kernelPackages = kernelPackages;
  boot.extraModulePackages = [ (kernelPackages.callPackage ../pkgs/ov05c10 { }) ];

  # Same options as Ubuntu's working entry (from the live ISO's Acer entry), plus cma=256M for the camera's
  # soft-ISP buffers. stubble.dtb_override is Ubuntu-stub specific and not needed with a plain Image.
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "regulator_ignore_unused"
    "efi=noruntime"
    "id_aa64mmfr0.ecv=1"
    "modprobe.blacklist=gpi"
    "cma=256M"
    # The firmware has a TPM2 (Qualcomm fTPM in the secure world, TPMEventLog in the EFI tables, and systemd-boot
    # reports it), but Linux has no driver for it ("ima: No TPM chip found"). systemd-tpm2-generator then makes
    # tpm2.target wait for /dev/tpm0 + /dev/tpmrm0: 90 s in the initrd and 90 s again after switch-root, which also
    # pushes module loading past the kernel's 10 s deferred-probe deadline.
    "systemd.tpm2_wait=0"
  ];
  systemd.tpm2.enable = false;
  boot.initrd.systemd.tpm2.enable = false;

  # The NixOS default initrd module list is x86-centric and partly missing from this config.
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = [
    "nvme"
    "btrfs"
    # Internal keyboard (I2C HID), for the initrd emergency shell.
    "i2c-qcom-geni"
    "i2c-hid-of"
    "hid-generic"
  ];
  # Supplier drivers that are modules but that other devices wait for (fw_devlink). Ubuntu's dracut initramfs
  # loads all of them before 1.6 s. Without fixed + tcsrcc the NVMe never appears (PCIe controller defers forever:
  # `fixed` = regulator-nvme and vph-pwr, `tcsrcc` = PCIe PHY reference clock). The kernel stops waiting for
  # missing suppliers ~10 s after boot, and then e.g. the GPU SMMU (gpucc) and SCMI (cpucp mailbox) fail for good
  # with -110, so the rest is loaded early too. Nothing in this list needs firmware.
  boot.initrd.kernelModules = [
    "fixed"
    "tcsrcc-x1e80100"
    "qcom-cpucp-mbox"
    "gpucc-x1p42100"
    "dispcc-x1e80100"
    "camcc-x1p42100"
    "videocc-sm8550"
    "phy-nxp-ptn3222"
    "phy-qcom-edp"
    "qcom-pbs"
    "ubwc_config"
    "socinfo"
  ];

  # i2c-dev for the EC tools.
  boot.kernelModules = [ "i2c-dev" ];

  hardware.deviceTree = {
    enable = true;
    name = "qcom/x1p42100-acer-swift-go14-01.dtb";
    dtbSource = pkgs.callPackage ../pkgs/dtb { inherit kernel; };
  };

  # The DSP/GPU drivers are modules that load from the root filesystem here (not from the initrd as on Ubuntu),
  # so the firmware only has to be in the system closure.
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ (pkgs.callPackage ../pkgs/acer-firmware.nix { src = acer-firmware; }) ];

  hardware.bluetooth.enable = true;

  # Camera: apps reach it through PipeWire/WirePlumber's libcamera monitor. Give the video group udmabuf so it
  # doesn't depend on logind's uaccess ACL racing WirePlumber at login.
  services.udev.extraRules = ''
    KERNEL=="udmabuf", GROUP="video", MODE="0660"
  '';

  # EC host mode (keyboard backlight Fn+F11), at boot and after resume.
  environment.systemPackages = [ acer-ec ];
  systemd.services.acer-ec-hostmode = {
    description = "Acer SFG14-01: enable EC host mode (keyboard backlight Fn+F11, as Windows does)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    unitConfig.ConditionPathExists = "/sys/bus/platform/devices/b94000.i2c";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${acer-ec}/bin/acer-ec-hostmode";
    };
  };
  powerManagement.resumeCommands = ''
    ${acer-ec}/bin/acer-ec-hostmode 2>&1 | ${pkgs.util-linux}/bin/logger -t acer-ec-hostmode || true
  '';
}
