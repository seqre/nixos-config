# The same DTB chain Ubuntu boots as /boot/dtb-cleanup (see ~/ISSUES.md):
#   kernel DTB (retimer fix is a kernel patch here, an fdtput on Ubuntu)
#   + camera overlay + fingerprint overlay + cleanup overlay
#   + delete enable-gpios/pinctrl-* from the BT node (overlays can't delete properties).
{
  stdenv,
  dtc,
  kernel,
}:

let
  name = "x1p42100-acer-swift-go14-01";
  overlays = [
    "camera"
    "fingerprint"
    "cleanup"
  ];
in
stdenv.mkDerivation {
  pname = "secomet-dtbs";
  version = kernel.version;
  src = ./.;
  nativeBuildInputs = [ dtc ];

  buildPhase = ''
    runHook preBuild
    K=${kernel.src}
    cp ${kernel}/dtbs/qcom/${name}.dtb base.dtb
    chmod u+w base.dtb
    for o in ${toString overlays}; do
      cpp -nostdinc -undef -x assembler-with-cpp \
        -I $K/include -I $K/scripts/dtc/include-prefixes \
        ${name}-$o.dtso -o $o.pre.dtso
      dtc -@ -q -I dts -O dtb -o $o.dtbo $o.pre.dtso
      fdtoverlay -i base.dtb -o next.dtb $o.dtbo
      mv next.dtb base.dtb
    done
    BT=/soc@0/geniqup@ac0000/serial@a98000/bt_wcn7850
    for p in enable-gpios pinctrl-0 pinctrl-names; do fdtput -d base.dtb $BT $p; done
    runHook postBuild
  '';

  installPhase = ''
    install -Dm644 base.dtb $out/qcom/${name}.dtb
  '';
}
