# Printing to the HP Color LaserJet M553 (USB 03f0:382a) over IPP-over-USB (class 7/1/4): ipp-usb turns it into an
# IPP printer on localhost and advertises it through avahi.
#
# The queue sends PostScript. Left alone, CUPS makes a driverless (IPP Everywhere) queue that sends PDF, and this
# printer drops PDFs: it wakes up, reports the job completed with 0 sheets and prints nothing. PostScript prints.
#
# The queue is declared because CUPS state (/var/lib/cups) is not persisted (modules/impermanence.nix): queues added
# by hand (GNOME Settings, lpadmin) are gone after a reboot. ensurePrinters runs lpadmin in cups.service's postStart;
# with a PPD (not `-m everywhere`) it never contacts the printer, so CUPS starts fine while it is unplugged.
{ pkgs, ... }:

let
  name = "HP_Color_LaserJet_M553_24B28F_USB";

  # HP's PPD for the M553, from hplip, without its `hpps` filter (which only adds HP job-accounting PJL), so the
  # system doesn't pull in hplip's ~1 GB closure: CUPS sends plain PostScript. Only the PPD text ends up in $out.
  m553-ppd = pkgs.runCommand "hp-color-laserjet-m553-ppd" { } ''
    mkdir -p $out/share/cups/model
    ${pkgs.gzip}/bin/zcat ${pkgs.hplip}/share/cups/model/HP/hp-color_laserjet_m553-ps.ppd.gz \
      | ${pkgs.gnused}/bin/sed '/^\*cupsFilter: .*hpps"$/d' > $out/share/cups/model/hp-color_laserjet_m553-ps.ppd
  '';
in
{
  services.printing = {
    enable = true;
    drivers = [ m553-ppd ];
    # cups-browsed would add a queue for every printer on whatever network the laptop joins; not needed for a
    # declared queue.
    browsed.enable = false;
  };
  services.ipp-usb.enable = true;

  hardware.printers = {
    ensurePrinters = [
      {
        # The name CUPS gives the advertised printer, so this queue shadows the PDF one CUPS would offer next to it.
        inherit name;
        description = "HP Color LaserJet M553";
        location = "USB";
        # Not the dnssd:// URI: it resolves to secomet.local, which the LAN's DNS search domain answers with another
        # host. The port is ipp-usb's, kept per device in /var/lib/ipp-usb/dev (persisted).
        deviceUri = "ipp://localhost:60000/ipp/print";
        model = "hp-color_laserjet_m553-ps.ppd";
        ppdOptions = {
          PageSize = "A4"; # the PPD defaults to Letter
          Duplex = "None";
        };
      }
    ];
    ensureDefaultPrinter = name;
  };
}
