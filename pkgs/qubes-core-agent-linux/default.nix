{
  callPackage,
  enableNetworking ? false,
}:
callPackage ./generic.nix {
  version = "4.3.47";
  hash = "sha256-nOr7AxTRBXP1lvK5b/gSZzC8rX47v3278/yXrxKWls8=";
  inherit enableNetworking;
}
