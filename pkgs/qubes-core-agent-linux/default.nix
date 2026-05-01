{
  callPackage,
  enableNetworking ? false,
}:
callPackage ./generic.nix {
  version = "4.3.40";
  hash = "sha256-QT3DNX2lh1vTmfgGK6kXDLFqtImFc4zVKsofCUIPvXs=";
  inherit enableNetworking;
}
