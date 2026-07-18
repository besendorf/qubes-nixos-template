{
  lib,
  fetchFromGitHub,
  nixpkgs,
  pkgs,
  nixosConfig,
  qubesVersion,
}: let
  version = "4.0.6";
  rootImg = lib.overrideDerivation
    (import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
      inherit lib pkgs;
      config = nixosConfig.config;
      contents = [
        {
          source = ../examples/configuration.nix;
          target = "/etc/nixos/configuration.nix";
        }
        {
          source = ../examples/flake.nix;
          target = "/etc/nixos/flake.nix";
        }
      ];
      diskSize = 12288; # 12G
      partitionTableType = "hybrid";
      name = "root";
    })
    (_: {
      # QEMU falls back to TCG when KVM is unavailable. Requiring the KVM
      # feature prevents builds in Qubes VMs before QEMU can do so.
      requiredSystemFeatures = [];

      # QEMU's TCG fallback can crash in the virtiofs I/O path with multiple
      # vCPUs. Image finalization is I/O-bound, so keep this VM single-core.
      enableParallelBuilding = false;
    });
in
  pkgs.stdenvNoCC.mkDerivation {
    name = "qubes-template-rpm";

    src = fetchFromGitHub {
      owner = "QubesOS";
      repo = "qubes-linux-template-builder";
      rev = "v${version}";
      hash = "sha256-ABfhqyg9PypuKWYe6yhEr99hxf7qWsYCwRyToGhPKZA=";
    };

    nativeBuildInputs = [
      pkgs.rpm
      pkgs.coreutils
      pkgs.gnutar
    ];

    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      set -x

      mkdir -p qubeized_images/nixos
      ln -s ${rootImg}/nixos.img qubeized_images/nixos/root.img

      cp -r ${../appmenus} appmenus
      cp template_generic.conf template.conf

      date +"%Y%m%d%H%M" > build_timestamp_nixos
      echo ${qubesVersion} > version

      substituteInPlace templates.spec --replace qubeized_images "$(pwd)/qubeized_images"
      substituteInPlace templates.spec --replace " appmenus" " $(pwd)/appmenus"
      substituteInPlace templates.spec --replace " template.conf" " $(pwd)/template.conf"

      DIST=nixos ./build_template_rpm nixos
    '';

    installPhase = ''
      mkdir $out/
      mv rpm/noarch/*.rpm $out/
    '';
  }
