{
  description = "nixos templatevm configurations";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    lib = nixpkgs.lib;
    system = "x86_64-linux";
    qubesPackages = final: prev: {
      qubes-core-qubesdb = prev.callPackage ./pkgs/qubes-core-qubesdb {};
      qubes-core-vchan-xen = prev.callPackage ./pkgs/qubes-core-vchan-xen {};
      qubes-core-qrexec = prev.callPackage ./pkgs/qubes-core-qrexec {};
      qubes-core-agent-linux = prev.callPackage ./pkgs/qubes-core-agent-linux {};
      qubes-linux-utils = prev.callPackage ./pkgs/qubes-linux-utils {};
      qubes-gui-common = prev.callPackage ./pkgs/qubes-gui-common {};
      qubes-gui-agent-linux = prev.callPackage ./pkgs/qubes-gui-agent-linux {};
      qubes-sshd = prev.callPackage ./pkgs/qubes-sshd {};
      qubes-usb-proxy = prev.callPackage ./pkgs/qubes-usb-proxy {};
      qubes-gpg-split = prev.callPackage ./pkgs/qubes-gpg-split {};
    };
    patched-nix-update = final: prev: {
      nix-update =
        prev.nix-update
        .overrideAttrs
        (finalAttrs: previousAttrs: {
          patches = [./pkgs/nix-update/0000-fetch-from-tags.patch];
        });
    };

    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        qubesPackages
        patched-nix-update
      ];
    };
  in rec {
    overlays.default = qubesPackages;
    nixosModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: {
      imports = [
        ./modules/qubes/core.nix
        ./modules/qubes/db.nix
        ./modules/qubes/gui.nix
        ./modules/qubes/networking.nix
        ./modules/qubes/qrexec.nix
        ./modules/qubes/sshd.nix
        ./modules/qubes/updates.nix
        ./modules/qubes/usb.nix
      ];
    };
    nixosProfiles.default = {
      config,
      lib,
      pkgs,
      ...
    }: {
      imports = [
        ./profiles/qubes.nix
      ];
    };
    nixosConfigurations = {
      nixos =
        lib.nixosSystem
        {
          inherit pkgs system;
          modules = [
            self.nixosModules.default
            self.nixosProfiles.default
            ./examples/configuration.nix
          ];
        };
      iso = lib.nixosSystem {
        inherit system;
        specialArgs = {
          targetSystem = nixosConfigurations.nixos;
        };
        modules = [
          ./tools/iso.nix
        ];
      };
    };
    rpm = pkgs.callPackage ./tools/rpm.nix {
      inherit nixpkgs;
      qubesVersion = "4.3.0";
      nixosConfig = nixosConfigurations.nixos;
    };
    iso = nixosConfigurations.iso.config.system.build.isoImage;

    checks.x86_64-linux.nix-proxy-integration =
      assert lib.elem "qubes-sysinit.service" nixosConfigurations.nixos.config.systemd.sockets.qubes-updates-proxy-forwarder.after;
        pkgs.runCommand "nix-proxy-integration-check" {} ''
          wrappers=${nixosConfigurations.nixos.config.system.build.qubesNixProxyWrappers}

          for program in nix nix-shell nix-store nixos-rebuild; do
            test -x "$wrappers/bin/$program"
          done

          grep -q /run/qubes-service/updates-proxy-setup "$wrappers/bin/nix"
          grep -q http://127.0.0.1:8082/ "$wrappers/bin/nix"
          "$wrappers/bin/nix" --version >/dev/null
          touch "$out"
        '';

    checks.x86_64-linux.rootfs-resize-integration =
      assert lib.elem "multi-user.target" nixosConfigurations.nixos.config.systemd.services.qubes-rootfs-resize.wantedBy;
        pkgs.runCommand "rootfs-resize-integration-check" {} ''
          agent=${pkgs.qubes-core-agent-linux}
          resize_rpc="$agent/etc/qubes-rpc/qubes.ResizeDisk"

          test -x "$agent/lib/qubes/resize-rootfs"
          test -x "$resize_rpc"
          grep -Fq "$agent/lib/qubes/resize-rootfs" "$resize_rpc"
          ! grep -Fq /usr/lib/qubes/resize-rootfs "$resize_rpc"

          resize_if_needed="$agent/lib/qubes/init/resize-rootfs-if-needed.sh"
          grep -Fq 'root_device_name=''${root_device##*/}' "$resize_if_needed"
          grep -Fq '/sys/class/block/$root_device_name/start' "$resize_if_needed"
          ! grep -Fq 'boot_data_size=$((203 * 2 * 1024))' "$resize_if_needed"
          touch "$out"
        '';

    # Expose only the custom qubes packages (not all of nixpkgs) so that
    # `nix build .#rpm` resolves to the template RPM above rather than being
    # shadowed by `pkgs.rpm` within nixpkgs.
    #
    # The `update.sh` script uses `nix-update` to target patching.
    packages.x86_64-linux = {
      inherit
        (pkgs)
        qubes-core-qubesdb
        qubes-core-vchan-xen
        qubes-core-qrexec
        qubes-core-agent-linux
        qubes-linux-utils
        qubes-gui-common
        qubes-gui-agent-linux
        qubes-sshd
        qubes-usb-proxy
        qubes-gpg-split
        nix-update
        ;
      inherit rpm iso;
    };
  };
}
