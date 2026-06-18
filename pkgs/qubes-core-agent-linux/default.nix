{
  callPackage,
  enableNetworking ? false,
}:
callPackage ./generic.nix {
  version = "4.3.45";
  hash = "sha256-cdqGWw/ock12VVUCbIFNDMV8NxNtHuW+9SzX6T6oZIk=";
  inherit enableNetworking;
}
