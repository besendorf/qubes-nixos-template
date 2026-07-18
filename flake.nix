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
      qubesVersion = "4.2.0";
      nixosConfig = nixosConfigurations.nixos;
    };
    iso = nixosConfigurations.iso.config.system.build.isoImage;
    checks.x86_64-linux.application-menu-integration = let
      agent = pkgs.qubes-core-agent-linux;
      systemPath = nixosConfigurations.nixos.config.system.path;
    in
      pkgs.runCommand "application-menu-integration-check" {} ''
        test -x ${agent}/bin/qvm-features-request
        ${agent}/bin/qvm-features-request --help >/dev/null

        start_app=${agent}/etc/qubes-rpc/qubes.StartApp
        test -x "$start_app"
        if "$start_app" >start-app.out 2>start-app.err; then
          echo "qubes.StartApp unexpectedly accepted a missing argument" >&2
          exit 1
        fi
        grep -Fq 'This service requires an argument' start-app.err
        ! grep -Fq /usr/bin/python3 "$start_app"
        grep -Fq /run/current-system/sw/share \
          ${agent}/etc/qubes-rpc/.qubes.StartApp-wrapped

        post_install=${agent}/etc/qubes-rpc/qubes.PostInstall
        sync_hook=${agent}/lib/qubes/qubes-trigger-sync-appmenus.sh
        grep -Eq '/nix/store/[^/]+-qubes-core-agent-linux[^/]*/etc/qubes/post-install.d/' "$post_install"
        grep -Eq '/nix/store/[^/]+-qubes-core-agent-linux[^/]*/etc/qubes-rpc/qubes.GetAppmenus' "$sync_hook"
        grep -Fq '${agent}/bin/qvm-features-request' "$post_install" ||
          grep -Eq 'PATH="/nix/store/[^/]+-qubes-core-agent-linux[^/]*/bin:' "$post_install"
        ! grep -Fq /usr/lib/qubes/qubes-trigger-sync-appmenus.sh \
          ${agent}/etc/qubes/post-install.d/10-qubes-core-agent-appmenus.sh

        for list in \
          ${./appmenus}/whitelisted-appmenus.list \
          ${./appmenus}/vm-whitelisted-appmenus.list \
          ${./appmenus}/netvm-whitelisted-appmenus.list; do
          while IFS= read -r desktop_id; do
            test -n "$desktop_id"
            test -f "${systemPath}/share/applications/$desktop_id"
          done < "$list"
        done

        touch "$out"
      '';

    packages.x86_64-linux = pkgs;
  };
}
