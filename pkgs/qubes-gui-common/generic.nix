{
  lib,
  stdenv,
  fetchFromGitHub,
  version,
  hash,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qubes-gui-common";
  inherit version;

  src = fetchFromGitHub {
    owner = "QubesOS";
    repo = finalAttrs.pname;
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  buildPhase = ''
    true
  '';

  installPhase = ''
    mkdir -p $out/include
    cp include/*.h $out/include/
  '';

  meta = {
    description = "Common files for Qubes GUI - protocol headers";
    homepage = "https://qubes-os.org";
    license = lib.licenses.gpl2Plus;
    maintainers = [];
    platforms = lib.platforms.linux;
  };
})
