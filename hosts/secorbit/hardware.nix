# secorbit's hardware: Intel CPU, NVIDIA GPU, fingerprint reader, battery.
{ config, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  # The NVIDIA driver is unfree: nixpkgs.config.allowUnfree is set in default.nix.
  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.fprintd.enable = true;

  # Stop charging at 80%.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{charge_control_end_threshold}="80"
  '';
}
