{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.services.qubes.updates = {
    check = mkEnableOption "enable updates check, can be resource intensive due to required nix build";
    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--update-input"
        "nixpkgs"
        "--update-input"
        "qubes-nixos-template"
      ];
      example = [
        "-I"
        "stuff=/home/alice/nixos-stuff"
        "--option"
        "extra-binary-caches"
        "http://my-cache.example.org/"
      ];
      description = ''
        Any additional flags passed to {command}`nixos-rebuild`, used for both the check and actual update.

        If you are using flakes and use a local repo you can add
        {command}`[ "--update-input" "nixpkgs" "--commit-lock-file" ]`
        to update nixpkgs.
      '';
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = [pkgs.git pkgs.openssh];
      description = ''
        Any additional packages which should be available in the path for {command}`nixos-rebuild`, used for both the check and actual update.
      '';
    };
  };
  config = mkMerge [
    (
      mkIf config.services.qubes.updates.check {
        systemd.timers.qubes-update-check = {
          wantedBy = ["timers.target"];
        };
      }
    )
    (
      let
        proxyEnvironment = ''
          if [ -e /run/qubes-service/updates-proxy-setup ]; then
            qubes_proxy=http://127.0.0.1:8082/
            proxy_default="''${all_proxy:-''${ALL_PROXY:-$qubes_proxy}}"

            export http_proxy="''${http_proxy:-''${HTTP_PROXY:-$proxy_default}}"
            export https_proxy="''${https_proxy:-''${HTTPS_PROXY:-$proxy_default}}"
            export all_proxy="$proxy_default"
            export HTTP_PROXY="''${HTTP_PROXY:-$http_proxy}"
            export HTTPS_PROXY="''${HTTPS_PROXY:-$https_proxy}"
            export ALL_PROXY="''${ALL_PROXY:-$all_proxy}"

            no_proxy_default="''${no_proxy:-''${NO_PROXY:-127.0.0.1,localhost}}"
            export no_proxy="$no_proxy_default"
            export NO_PROXY="''${NO_PROXY:-$no_proxy}"
          fi
        '';

        nixProxyWrappers = pkgs.runCommand "qubes-nix-proxy-wrappers" {
          nativeBuildInputs = [pkgs.makeWrapper];
          meta.priority = 1;
        } ''
          mkdir -p "$out/bin"

          for program in ${config.nix.package.out}/bin/*; do
            [ -x "$program" ] || continue
            name=$(${pkgs.coreutils}/bin/basename "$program")
            makeWrapper "$program" "$out/bin/$name" \
              --run ${lib.escapeShellArg proxyEnvironment}
          done

          makeWrapper ${config.system.build.nixos-rebuild}/bin/nixos-rebuild \
            "$out/bin/nixos-rebuild" \
            --run ${lib.escapeShellArg proxyEnvironment}
        '';

        upgradesStatusNotify = pkgs.writeShellScriptBin "upgrades-status-notify" ''
          set -e

          export PATH=${lib.makeBinPath config.services.qubes.updates.extraPackages}:$PATH
          ${proxyEnvironment}

          if [ "$1" = "started-by-init" ]; then
              true "INFO: Started by systemd unit (timer.) Continuing..."
          else
              true "INFO: Not started by systemd unit (timer.) Probably started by package manager hook script."
              if test -e /run/qubes/persistent-full; then
                  true "INFO: Running inside Template and Standalone. Continuing..."
              else
                  true "INFO: Probably running inside App Qube. Stop."
                  exit 0
              fi
          fi

          # FIXME a lot of assumptions here...
          tempdir=$(mktemp -d /tmp/tmp.nix-updateinfo.XXX)
          cp -r /etc/nixos/. $tempdir
          cd $tempdir
          ${config.nix.package.out}/bin/nix build ".#nixosConfigurations.$(${pkgs.nettools}/bin/hostname).config.system.build.toplevel" ${toString config.services.qubes.updates.flags} 1>&2
          nix_diff=$(${config.nix.package.out}/bin/nix store diff-closures /run/current-system ./result \
            | ${pkgs.gawk}/bin/awk '/[0-9] →|→ [0-9]/ && !/nixos/' || true)
          echo "$nix_diff" 1>&2
          if [ -z "$nix_diff" ]; then
            ${pkgs.qubes-core-qrexec}/lib/qubes/qrexec-client-vm dom0 qubes.NotifyUpdates /bin/sh -c 'echo 0'
          else
            ${pkgs.qubes-core-qrexec}/lib/qubes/qrexec-client-vm dom0 qubes.NotifyUpdates /bin/sh -c 'echo 1'
          fi
          cd ~-
          rm -rf "$tempdir"
        '';

        getPackages = pkgs.writeShellScriptBin "qubes-nixos-get-packages" ''
          ${proxyEnvironment}
          empty=$(${config.nix.package.out}/bin/nix build --impure --no-link --print-out-paths --expr '(with import <nixpkgs> { }; pkgs.runCommand "empty" { } "mkdir -p $out")')
          ${config.nix.package.out}/bin/nix store diff-closures "$empty" /run/current-system | ${pkgs.gawk}/bin/awk '/→ [0-9]/ && !/nixos/' |  ${pkgs.gnused}/bin/sed 's/\x1b\[[0-9;]*m//g'
        '';

        nixosRebuildWrapper = pkgs.writeShellScriptBin "qubes-nixos-rebuild" ''
          export PATH=${lib.makeBinPath config.services.qubes.updates.extraPackages}:$PATH
          ${proxyEnvironment}

          # by default switch to the new generation, updating the system
          if [ $# -eq 0 ]; then
            ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch ${toString config.services.qubes.updates.flags}
          else
            ${config.system.build.nixos-rebuild}/bin/nixos-rebuild "$@"
          fi
        '';

        vmexec = pkgs.writeTextFile {
          name = "qubes-rpc-vmexec";
          # NOTE: in order to perform updates, qubes `vmupdate` injects a python agent into the vm and then
          # executes it. the agent then calls our scripts to perform various actions.
          # we need to ensure the VMExec RPC has the correct PATH to find the dependencies and
          # our update scripts.
          text = ''
            #!${pkgs.stdenv.shell}

            export PATH=${lib.makeBinPath (with pkgs; [coreutils gnutar python3 upgradesStatusNotify getPackages nixosRebuildWrapper])}:$PATH
            exec ${config.services.qubes.core.package.out}/bin/qubes-vmexec "$@"
          '';
          executable = true;
          destination = "/etc/qubes-rpc/qubes.VMExec";
        };
      in {
        environment.systemPackages = [
          nixProxyWrappers
          nixosRebuildWrapper
        ];
        system.build.qubesNixProxyWrappers = nixProxyWrappers;
        services.qubes.qrexec.packages = [vmexec];
        systemd.services.qubes-update-check = {
          serviceConfig = {
            ExecStart = ["" "${upgradesStatusNotify}/bin/upgrades-status-notify started-by-init"];
          };
        };
      }
    )
  ];
}
