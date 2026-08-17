{
  lib,
  stdenv,
  fetchFromGitHub,
  xen,
  version,
  hash,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qubes-core-vchan-xen";
  inherit version;

  src = fetchFromGitHub {
    owner = "QubesOS";
    repo = finalAttrs.pname;
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  buildInputs = [xen];

  buildPhase = ''
    make all PREFIX=/ LIBDIR="$out/lib" INCLUDEDIR="$out/include"
  '';

  installPhase = ''
    make install DESTDIR=$out PREFIX=/
  '';

  env.CFLAGS = "-DHAVE_XC_DOMAIN_GETINFO_SINGLE";

  meta = {
    description = "Libraries required for the higher-level Qubes daemons and tools";
    homepage = "https://qubes-os.org";
    license = lib.licenses.gpl2Plus;
    maintainers = [];
    platforms = lib.platforms.linux;
  };
})
