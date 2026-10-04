# EC tools from Ubuntu's /usr/local/sbin (see ~/ISSUES.md, "Keyboard backlight"):
#   ec-rw REG [VALUE], ec-dump, acer-ec-hostmode.
{
  stdenvNoCC,
  lib,
  makeWrapper,
  coreutils,
  gnused,
  i2c-tools,
}:

stdenvNoCC.mkDerivation {
  pname = "acer-ec-tools";
  version = "1";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    for f in ec-rw ec-dump acer-ec-hostmode; do
      install -Dm755 $f $out/bin/$f
    done
    # acer-ec-hostmode pins an Ubuntu PATH; use the wrapper's instead.
    sed -i '/^PATH=/d' $out/bin/acer-ec-hostmode
    for f in $out/bin/*; do
      wrapProgram $f --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gnused
          i2c-tools
        ]
      }:$out/bin
    done
  '';
}
