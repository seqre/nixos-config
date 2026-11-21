# secorbit as an always-on remote machine: works with the lid closed, suspends itself when nobody uses it, and wakes
# up from a Wake-on-LAN magic packet.
#
# Waking it: magic packets are layer-2 broadcasts, which Tailscale doesn't carry, so they have to be sent from a
# machine on the same LAN; the `wake-secorbit` alias on secomet (home/seqre.nix) sends one from the home LAN. MACs:
#   - 10:98:19:55:18:35  Realtek USB NIC in the USB-C hub: **wakes it** (tested 2026-11-21). Keep the hub in the same
#                        USB-C port; it works because that port stays powered in S3.
#   - 48:2a:e3:73:ae:02  onboard Intel I219-V (needs Lenovo's ethernet extension adapter): the one Lenovo supports;
#                        untested, no adapter in use.
#   - Wi-Fi (WoWLAN) didn't wake it, so it's not enabled: it would keep the radio associated in S3 for nothing.
# Firmware: F1 → Config → Network → Wake On LAN = "AC Only" (or "AC and Battery"); for the USB-C hub also
# Config → Thunderbolt 3 → "Wake by Thunderbolt(TM) 3" = Enabled.
{ pkgs, ... }:

{
  # Lid closed: keep running (logind's default would suspend).
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Wake-on-LAN by magic packet, as the NetworkManager default for every wired connection profile whose own setting
  # is "default" (the default). NetworkManager applies it when it activates the connection, and only accepts numbers
  # here: MAGIC = 0x40.
  networking.networkmanager.settings.connection."ethernet.wake-on-lan" = 64;

  # Suspend when idle. autosuspend checks every `interval` seconds; when no check reports activity for `idle_time`
  # seconds it suspends (deep/S3). After resuming the idle timer starts over, so there are 15 minutes to connect
  # after a wake-up. Logs: `journalctl -u autosuspend`.
  #
  # Keep it awake explicitly: `systemd-inhibit --what=sleep <cmd>` (any blocking sleep/idle/shutdown inhibitor
  # prevents suspending; GNOME's "delay" inhibitors don't).
  services.autosuspend = {
    enable = true;
    settings = {
      interval = 60;
      idle_time = 900;
    };
    checks = {
      # An SSH connection (shell, port forward, editor remote, rsync, sshfs).
      Ssh = {
        class = "ActiveConnection";
        ports = "22";
      };
      # Keyboard input in any terminal in the last 2 minutes. Covers mosh, whose session outlives the SSH
      # connection: an attached-but-unused mosh session doesn't keep the machine up, and survives the suspend.
      TerminalInput = {
        class = "ExternalCommand";
        command = "${pkgs.findutils}/bin/find /dev/pts -maxdepth 1 -name '[0-9]*' -amin -2 | ${pkgs.gnugrep}/bin/grep -q .";
      };
      # CPU jobs: 5-minute load average.
      Load.threshold = 0.8;
      # A CUDA process (only CUDA opens nvidia-uvm; checking doesn't wake the GPU). The node is gone while the
      # driver is unloaded.
      Cuda = {
        class = "ExternalCommand";
        command = "test -e /dev/nvidia-uvm && ${pkgs.psmisc}/bin/fuser -s /dev/nvidia-uvm";
      };
      # Someone at the machine: a graphical session that GNOME hasn't marked idle (Settings → Power → Screen Blank).
      # The login screen is class "greeter" and doesn't count.
      LocalSession = {
        class = "LogindSessionsIdle";
        types = "wayland,x11";
      };
    };
  };

  # The login screen would otherwise suspend after 15 minutes on its own, ignoring the checks above. In the user
  # session GNOME's automatic suspend is already off.
  services.displayManager.gdm.autoSuspend = false;
}
