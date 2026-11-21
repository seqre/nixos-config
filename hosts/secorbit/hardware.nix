# secorbit's hardware: ThinkPad X1 Extreme Gen 2 (20QV), Intel i7-9750H (UHD 630), NVIDIA GTX 1650 Max-Q (TU117,
# Turing), fingerprint reader, battery.
{ config, lib, pkgs, ... }:

let
  # The NVIDIA GPU's PCI address, in sysfs form. Same device as hardware.nvidia.prime.nvidiaBusId.
  nvidiaPci = "0000:01:00.0";

  # While this file exists, the NVIDIA kernel modules may load. /run is a tmpfs, so every boot starts with it absent.
  enabledFlag = "/run/nvidia-power-on";

  # Used as the modprobe `install` command of every NVIDIA module: loads it only while enabledFlag exists, otherwise
  # does nothing and succeeds (so systemd-modules-load and udev's modalias loading don't log failures).
  modprobeGate = pkgs.writeShellScript "nvidia-modprobe-gate" ''
    if [ -e ${enabledFlag} ]; then
      exec ${pkgs.kmod}/bin/modprobe --ignore-install "$@"
    fi
  '';
  gatedModules = [ "nvidia" "nvidia_uvm" "nvidia_modeset" "nvidia_drm" ];

  nvidia-power = pkgs.writeShellApplication {
    name = "nvidia-power";
    runtimeInputs = [ pkgs.kmod pkgs.psmisc pkgs.systemd pkgs.coreutils ];
    text = ''
      dev=/sys/bus/pci/devices/${nvidiaPci}
      loaded() { [ -d "/sys/module/$1" ]; }
      as_root() { if [ "$(id -u)" -ne 0 ]; then exec sudo "$(readlink -f "$0")" "$@"; fi; }
      # Processes holding an NVIDIA device open (fuser -v prints to stderr, with a header line).
      users() {
        local f files=()
        for f in /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-modeset /dev/dri/by-path/pci-${nvidiaPci}-*; do
          if [ -e "$f" ]; then files+=("$f"); fi
        done
        if [ ''${#files[@]} -gt 0 ]; then fuser -v "''${files[@]}" 2>&1 | tail -n +2; fi
      }
      unload() {
        local m
        for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
          if loaded "$m"; then rmmod "$m" || return 1; fi
        done
        rm -f ${enabledFlag}
        # With no driver bound, the PCI core suspends the GPU and its root port, which cuts its power (D3cold).
        for f in /sys/bus/pci/devices/${lib.removeSuffix ".0" nvidiaPci}.*/power/control; do echo auto > "$f"; done
        echo "driver: off"
      }

      case "''${1:-status}" in
        status)
          # Reads sysfs only: doesn't wake the GPU (nvidia-smi does).
          if loaded nvidia_drm; then mode="display"; elif loaded nvidia; then mode="on (compute)"; else mode="off"; fi
          echo "driver: $mode"
          echo "power:  $(cat "$dev/power_state") (runtime $(cat "$dev/power/runtime_status"))"
          u=$(users || true)
          if [ -n "$u" ]; then echo "users:"; echo "$u"; fi
          ;;
        on | display)
          as_root "$@"
          touch ${enabledFlag}
          if [ "$1" = display ]; then modprobe nvidia_drm; fi
          modprobe nvidia_uvm
          udevadm settle
          echo "driver: $1"
          ;;
        off)
          as_root "$@"
          u=$(users || true)
          if [ -z "$u" ]; then
            unload
          elif [ "''${2:-}" != --logout ]; then
            echo "GPU in use, not turning it off:" >&2
            echo "$u" >&2
            if loaded nvidia_drm; then
              echo "To end the GNOME session (and everything running in it) and power it off: nvidia-power off --logout" >&2
            fi
            exit 1
          elif [ -e /dev/nvidia-uvm ] && fuser -s /dev/nvidia-uvm; then
            # They'd outlive the session and keep the GPU busy anyway.
            echo "CUDA processes are using the GPU, not ending the session:" >&2
            fuser -v /dev/nvidia-uvm >&2 || true
            exit 1
          else
            # As a system service: this terminal is probably part of the session being ended.
            systemd-run --unit=nvidia-power-logout --collect --quiet "$(readlink -f "$0")" logout-off
            echo "Ending the GNOME session; the login screen comes back on the Intel GPU." \
              "Log: journalctl -u nvidia-power-logout"
          fi
          ;;
        logout-off)
          # Run by `off --logout`. A plain logout isn't enough: the login screen would open the GPU again. So stop
          # GDM, end the graphical sessions, unload, and start GDM with only the Intel GPU left.
          as_root "$@"
          trap 'systemctl start display-manager.service' EXIT
          systemctl stop display-manager.service
          for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
            case "$(loginctl show-session "$s" -p Type --value)" in
              wayland | x11) loginctl terminate-session "$s" ;;
            esac
          done
          for _ in $(seq 30); do
            if [ -z "$(users || true)" ]; then break; fi
            sleep 1
          done
          u=$(users || true)
          if [ -n "$u" ]; then
            echo "Still in use after ending the session, leaving it on:"
            echo "$u"
            exit 1
          fi
          unload
          ;;
        *)
          echo "usage: nvidia-power [status|on|display|off [--logout]]" >&2
          exit 1
          ;;
      esac
    '';
  };

  # Per task: `nvidia-run <cmd>` turns the GPU on, runs cmd, and turns it off again if it was off before and nothing
  # else uses it by then.
  nvidia-run = pkgs.writeShellApplication {
    name = "nvidia-run";
    runtimeInputs = [ nvidia-power ];
    text = ''
      if [ $# -eq 0 ]; then echo "usage: nvidia-run <command> [args...]" >&2; exit 1; fi
      was_on=false
      if [ -d /sys/module/nvidia ]; then was_on=true; fi
      nvidia-power on >/dev/null
      rc=0
      "$@" || rc=$?
      if ! $was_on; then nvidia-power off >/dev/null 2>&1 || echo "nvidia-run: GPU still in use, left on" >&2; fi
      exit "$rc"
    '';
  };
in
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.graphics = {
    enable = true;
    # VA-API for the Intel GPU, which drives the desktop.
    extraPackages = [ pkgs.intel-media-driver ];
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  # NVIDIA: off (D3cold, no driver loaded) by default, turned on when needed.
  #
  # Needs **Hybrid Graphics** in the firmware (F1 → Config → Display → Graphics Device; "OS Detection for NVIDIA
  # Optimus" Disabled). In "Discrete Graphics" mode the Intel GPU isn't on the PCI bus and NVIDIA drives the panel.
  #
  # Why not the driver's own idle power-off (powerManagement.finegrained, RTD3): this firmware doesn't support it
  # (/proc/driver/nvidia/gpus/*/power says "Runtime D3 status: Not supported"), and with the driver loaded the GPU
  # stays on. With no driver bound, the kernel powers it off itself through the root port's ACPI power resources.
  # So the NVIDIA modules don't load at boot (modprobeGate), and the desktop runs on the Intel GPU.
  #
  #   nvidia-power status    driver state and D0/D3cold, without waking the GPU (nvidia-smi wakes it)
  #   nvidia-power on        load the compute driver (CUDA); stays on until `off` or a reboot
  #   nvidia-run <cmd>       on, run cmd, off again (if it was off and nothing else uses it)
  #   nvidia-power display   also load nvidia-drm: external monitors and `nvidia-offload <cmd>` (Steam:
  #                          `nvidia-offload %command%`). GNOME then holds the GPU.
  #   nvidia-power off       unload and power off; refuses while something uses the GPU
  #   nvidia-power off --logout
  #                          after `display`: end the GNOME session, power off, bring the login screen back on Intel
  #                          (refuses while CUDA jobs run)
  #
  # All external outputs (HDMI and USB-C DisplayPort) are wired to the NVIDIA GPU: without `display` only the
  # built-in panel works.
  #
  # The NVIDIA driver is unfree: nixpkgs.config.allowUnfree is set in default.nix.
  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Saves all of VRAM across suspend/resume instead of just the essentials.
    powerManagement.enable = true;

    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # nvidia-offload
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };

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

  boot.extraModprobeConfig = lib.concatMapStrings (m: "install ${m} ${modprobeGate} ${m} $CMDLINE_OPTS\n") gatedModules;

  environment.systemPackages = [ nvidia-power nvidia-run ];

  # Without a password, so jobs started over SSH or from scripts can switch the GPU.
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = map (arg: {
        command = "${nvidia-power}/bin/nvidia-power ${arg}";
        options = [ "NOPASSWD" ];
      }) [ "on" "display" "off" "off --logout" ];
    }
  ];

  services.fprintd.enable = true;

  services.udev.extraRules = ''
    # Stop charging at 80%.
    SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{charge_control_end_threshold}="80"

    # Runtime PM for the NVIDIA GPU and its HDMI audio function, so they power off while no driver is bound.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto"
  '';
}
