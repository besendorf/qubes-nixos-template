{
  fetchFromGitHub,
  lib,
  resholve,
  wrapGAppsNoGuiHook,
  stdenv,
  bash,
  coreutils,
  diffutils,
  e2fsprogs,
  dconf,
  desktop-file-utils,
  fakeroot,
  findutils,
  gawk,
  getent,
  gnome-packagekit,
  gnugrep,
  gobject-introspection,
  graphicsmagick,
  haveged,
  iproute2,
  kmod,
  librsvg,
  lsb-release,
  lvm2,
  mount,
  nettools,
  ntp,
  pandoc,
  parted,
  pkg-config,
  procps,
  psmisc,
  python3,
  python3Packages,
  qubes-core-qrexec,
  qubes-core-qubesdb,
  qubes-core-vchan-xen,
  qubes-linux-utils,
  gnused,
  shared-mime-info,
  socat,
  systemd,
  umount,
  util-linux,
  xdg-utils,
  libx11,
  zenity,
  # FIXME networking optional
  networkmanager,
  tinyproxy,
  nftables,
  conntrack-tools,
  enableNetworking ? false,
  version,
  hash,
}: let
  pythonProgramDeps =
    [qubes-core-qubesdb]
    ++ (with python3Packages; [dbus-python pygobject3 pyxdg]);
  # qubes-core-qubesdb contains a Python extension but is built with
  # stdenv.mkDerivation, so makePythonPath does not recognize it as a Python
  # module.  Add its site-packages directory explicitly.
  pythonProgramPath =
    "${qubes-core-qubesdb}/${python3.sitePackages}:"
    + python3Packages.makePythonPath pythonProgramDeps;
  scripts_using_functions = [
    "lib/qubes/init/qubes-early-vm-config.sh"
    "lib/qubes/init/qubes-sysinit.sh"
    "lib/qubes/init/misc-post.sh"
    "lib/qubes/init/mount-dirs.sh"
    "lib/qubes/init/setup-rwdev.sh"
    "lib/qubes/init/bind-dirs.sh"
  ];
  scripts =
    scripts_using_functions
    ++ [
      "etc/qubes-rpc/qubes.Filecopy"
      "etc/qubes-rpc/qubes.ResizeDisk"
      "etc/qubes-rpc/qubes.VMShell"
      "etc/qubes-rpc/qubes.WaitForSession"
      "lib/qubes/init/functions"
      "lib/qubes/init/setup-rw.sh"
      "lib/qubes/init/resize-rootfs-if-needed.sh"
      "lib/qubes/resize-rootfs"
      "lib/qubes/update-proxy-configs"
      "bin/qvm-copy"
      "bin/qvm-copy-to-vm"
      "bin/qvm-move"
      "bin/qvm-move-to-vm"
      "bin/qvm-open-in-dvm"
      "bin/qvm-run-vm"
    ];
in
  resholve.mkDerivation (finalAttrs: {
    inherit version;
    pname = "qubes-core-agent-linux";

    #PKG_CONFIG_SYSTEMD_SYSTEMDSYSTEMUNITDIR = "${placeholder "out"}/lib/systemd/system";

    src = fetchFromGitHub {
      owner = "QubesOS";
      repo = "qubes-core-agent-linux";
      tag = "v${finalAttrs.version}";
      inherit hash;
    };

    patches = [./dynamic-rootfs-offset.patch];

    nativeBuildInputs =
      [
        bash
        desktop-file-utils
        gobject-introspection
        lsb-release
        pandoc
        pkg-config
        python3
        qubes-core-qubesdb
        qubes-core-vchan-xen
        qubes-linux-utils
        shared-mime-info
        wrapGAppsNoGuiHook
        libx11
      ]
      ++ (with python3Packages; [
        wrapPython
        distutils
        setuptools
      ]);

    buildInputs =
      [
        coreutils
        dconf
        fakeroot
        gawk
        gnome-packagekit
        gnused
        graphicsmagick
        haveged
        iproute2
        librsvg
        ntp
        parted
        procps
        python3
        qubes-core-qrexec
        qubes-core-qubesdb
        qubes-core-vchan-xen
        qubes-linux-utils
        socat
        xdg-utils
        zenity
      ]
      ++ lib.optional enableNetworking networkmanager
      ++ lib.optional enableNetworking tinyproxy
      ++ lib.optional enableNetworking nftables
      ++ lib.optional enableNetworking conntrack-tools
      ++ (with python3Packages; [
        dbus-python
        pygobject3
        pyxdg
      ]);

    postPatch = ''
      substituteInPlace Makefile --replace 'SHELL = /bin/bash' 'SHELL = ${bash}/bin/bash'

      # skip installing qfile-unpacker / bin-qfile-unpacker as SUID
      sed -i 's/-m 4755/-m 755/g' qubes-rpc/Makefile

      # 4.3 unified qvm-{copy,move}{,-to-vm} into one qvm-copy script (others
      # become hardlinks at install time) and made paths relative via $scriptdir.
      # Rewrite back to absolute paths so the existing resholve fix entries match.
      sed -i 's#"\$scriptdir/qubes/#"/usr/lib/qubes/#g' qubes-rpc/qvm-copy
    '';

    buildPhase = ''
      # Fix for network tools paths
      # FIXME use substituteInPlace
      # sed 's:/sbin/ip:pkgs.iproute2/bin/ip:g' -i network/*
      # sed 's:/bin/grep:pkgs.grep/bin/grep:g' -i network/*

      # Fix for archlinux sbindir
      # FIXME use substituteInPlace
      # sed 's:/usr/sbin/ntpdate:/usr/bin/ntpdate:g' -i qubes-rpc/sync-ntp-clock

      for dir in qubes-rpc misc; do
          make -C "$dir"
      done
    '';

    # Don't move doc, needed in the subsequent packaging
    forceShare = ["man" "info"];

    # FIXME
    # - finish path fixup
    # - investigate which archlinux specific installs need replacement
    # - fixup services in lib/systemd/system/
    # - figure out how to adapt service dropins?
    installPhase =
      ''
        # install -D -m 0644 -- "boot/grub.qubes" "$out/etc/default/grub.qubes"
        make install-corevm \
            PYTHON_PREFIX_ARG="--prefix ." \
            DESTDIR="$out" \
            BINDIR=/bin \
            SBINDIR=/bin \
            LIBDIR=/lib \
            SYSLIBDIR=/lib \
            SYSTEM_DROPIN_DIR=/usr/lib/systemd/system \
            USER_DROPIN_DIR=/usr/lib/systemd/user \
            DIST=nixos \
            PYTHON=${python3}/bin/python3
        make -C app-menu install DESTDIR="$out" install BINDIR=/bin LIBDIR=/lib
        make -C misc install DESTDIR="$out" BINDIR=/bin LIBDIR=/lib SYSLIBDIR=/lib
        make -C qubes-rpc DESTDIR="$out" BINDIR=/bin LIBDIR=/lib install
        make -C qubes-rpc/caja DESTDIR="$out" BINDIR=/bin LIBDIR=/lib install
        make -C qubes-rpc/kde DESTDIR="$out" BINDIR=/bin LIBDIR=/lib install
        make -C qubes-rpc/nautilus DESTDIR="$out" BINDIR=/bin LIBDIR=/lib QUBESLIBDIR=/lib/qubes install
        make -C qubes-rpc/thunar DESTDIR="$out" BINDIR=/bin LIBDIR=/lib install

        # fixup symlinks, noBrokenSymlinks should only fail for symlinks pointing inside the store
        IFS=; while read -r i; do \
          case ''$i in \
            ('''|'#'*) continue;; \
            (*[!A-Za-z0-9._-]*) \
              printf 'ERROR: bad data directory "%s"\n' "''$i" >&2; exit 1;;\
          esac; \
          ln -sf "/run/current-system/sw/share/''$i" $out/usr/share/qubes/xdg-override; \
        done < misc/data-dirs
        rm $out/usr/share/applications/defaults.list

        # install cron bindmount
        mkdir -p "$out/lib/qubes-bind-dirs.d"
        install -m 0644 "filesystem/30_cron.conf" "$out/lib/qubes-bind-dirs.d/30_cron.conf"

        # nixos does not have /etc/skel, initialize_home() requires it
        substituteInPlace "$out/lib/qubes/init/functions" --replace "/etc/skel" "/var/empty"

        # Fixup paths
        substituteInPlace "$out/bin/qubes-session-autostart" --replace "QUBES_XDG_CONFIG_DROPINS = '/etc/qubes/autostart'" "QUBES_XDG_CONFIG_DROPINS = \"$out/etc/qubes/autostart\""

        # Qubes invokes this RPC service after a template update.  Keep the
        # hook directory in the package instead of assuming a mutable /etc.
        substituteInPlace "$out/etc/qubes-rpc/qubes.PostInstall" \
          --replace-fail '/etc/qubes/post-install.d/*.sh' "$out/etc/qubes/post-install.d/*.sh" \
          --replace-fail \
            'for script in ' \
            "export PATH=\"$out/bin:${qubes-core-qubesdb}/bin:${systemd}/bin:${coreutils}/bin:${gnugrep}/bin:${util-linux}/bin:\$PATH\"

for script in "

        # The app-menu post-install hook and its helper use FHS paths
        # upstream.  Point them at the package and the qrexec package so the
        # same hook works from the immutable Nix store.
        substituteInPlace "$out/etc/qubes/post-install.d/10-qubes-core-agent-appmenus.sh" \
          --replace-fail '/usr/lib/qubes/qubes-trigger-sync-appmenus.sh' "$out/lib/qubes/qubes-trigger-sync-appmenus.sh"
        substituteInPlace "$out/lib/qubes/qubes-trigger-sync-appmenus.sh" \
          --replace-fail '/usr/lib/qubes/init/functions' "$out/lib/qubes/init/functions" \
          --replace-fail '/usr/lib/qubes/qrexec-client-vm' '${qubes-core-qrexec}/lib/qubes/qrexec-client-vm' \
          --replace-fail '/etc/qubes-rpc/qubes.GetAppmenus' "$out/etc/qubes-rpc/qubes.GetAppmenus"

        # Feature advertisement also assumes an FHS installation.  In a
        # TemplateVM the persistent RPC services are the ones in this output.
        substituteInPlace "$out/etc/qubes/post-install.d/10-qubes-core-agent-features.sh" \
          --replace-fail '/usr/share/qubes/marker-vm' "$out/share/qubes/marker-vm" \
          --replace-fail '/usr/bin/qubes-gui' '/run/current-system/sw/bin/qubes-gui'
        substituteInPlace "$out/etc/qubes/post-install.d/10-qubes-core-agent-rpc.sh" \
          --replace-fail 'services_dir=/etc/qubes-rpc' "services_dir=$out/etc/qubes-rpc"

        # qubes.StartApp is outside $out/bin, so the Python setup hook does
        # not discover it automatically.  Give it a valid interpreter now;
        # postFixup wraps it with the package's Python dependencies below.
        substituteInPlace "$out/etc/qubes-rpc/qubes.StartApp" \
          --replace-fail '#!/usr/bin/python3 --' '#!${python3}/bin/python3' \
          --replace-fail \
            'import sys, os, pwd' \
            'import sys, os, pwd

# qrexec services do not run a login shell, so they do not inherit the NixOS
# profile paths.  pyxdg snapshots XDG_DATA_DIRS when it is imported below.
if "XDG_DATA_DIRS" not in os.environ:
    profile_home = os.path.expanduser("~")
    profile_state = os.environ.get(
        "XDG_STATE_HOME", os.path.join(profile_home, ".local", "state")
    )
    profile_user = pwd.getpwuid(os.getuid()).pw_name
    os.environ["XDG_DATA_DIRS"] = ":".join((
        os.path.join(profile_home, ".nix-profile", "share"),
        os.path.join(profile_state, "nix", "profile", "share"),
        os.path.join("/etc/profiles/per-user", profile_user, "share"),
        "/nix/var/nix/profiles/default/share",
        "/run/current-system/sw/share",
    ))'

        # Nix profiles can contain XDG paths that do not exist.  They are not
        # AppVM-local applications and should be skipped without noisy stat
        # errors during qubes.GetAppmenus.
        substituteInPlace "$out/etc/qubes-rpc/qubes.GetAppmenus" \
          --replace-fail '[ "$(stat -c %D "$dir")" = "$rw_devno" ]' \
                         '[ -e "$dir" ] && [ "$(stat -c %D "$dir")" = "$rw_devno" ]'

        # we lied about qrexec-client-vm not execing :)
        substituteInPlace "$out/bin/qvm-copy" --replace "/usr/lib/qubes/qfile-agent" "$out/lib/qubes/qfile-agent"
        substituteInPlace "$out/bin/qvm-copy-to-vm" --replace "/usr/lib/qubes/qfile-agent" "$out/lib/qubes/qfile-agent"
        substituteInPlace "$out/bin/qvm-move" --replace "/usr/lib/qubes/qfile-agent" "$out/lib/qubes/qfile-agent"
        substituteInPlace "$out/bin/qvm-move-to-vm" --replace "/usr/lib/qubes/qfile-agent" "$out/lib/qubes/qfile-agent"
        substituteInPlace "$out/bin/qvm-open-in-dvm" --replace "/bin/sh -c" "${bash}/bin/sh -c"
        substituteInPlace "$out/bin/qvm-open-in-dvm" --replace "/usr/lib/qubes/qopen-in-vm" "$out/lib/qubes/qopen-in-vm"
        substituteInPlace "$out/bin/qvm-run-vm" --replace "/usr/lib/qubes/qrun-in-vm" "$out/lib/qubes/qrun-in-vm"

        # first instance is an absolute path check, we could also just hardcode this to true
        substituteInPlace "$out/bin/qvm-open-in-dvm" --replace "/usr/bin/zenity" "${zenity}/bin/zenity"

        # use suid wrapper we will create in the module
        substituteInPlace "$out/etc/qubes-rpc/qubes.Filecopy" --replace "/usr/lib/qubes/qfile-unpacker" "/run/wrappers/bin/qfile-unpacker"

        for path in ${lib.concatStringsSep " " scripts_using_functions}; do
          substituteInPlace "$out/$path" --replace '/usr/lib/qubes/init/functions' "functions"
        done

        substituteInPlace "$out/lib/qubes/init/bind-dirs.sh" --replace "for source_folder in /usr/lib/qubes-bind-dirs.d /etc/qubes-bind-dirs.d /rw/config/qubes-bind-dirs.d ; do" "for source_folder in $out/lib/qubes-bind-dirs.d /rw/config/qubes-bind-dirs.d ; do"

        # Install systemd script allowing to automount /lib/modules
        # install -m 644 "archlinux/PKGBUILD.qubes-ensure-lib-modules.service" "$out/usr/lib/systemd/system/qubes-ensure-lib-modules.service"

        # Install pacman hook to update desktop icons
        # mkdir -p "$out/usr/share/libalpm/hooks/"
        # install -m 644 "archlinux/PKGBUILD.qubes-update-desktop-icons.hook" "$out/usr/share/libalpm/hooks/qubes-update-desktop-icons.hook"

        # Install pacman hook to notify dom0 about successful upgrade
        # install -m 644 "archlinux/PKGBUILD.qubes-post-upgrade.hook" "$out/usr/share/libalpm/hooks/qubes-post-upgrade.hook"

        # Install pacman.d drop-ins (at least 1 drop-in must be installed or pacman will fail)
        # mkdir -p -m 0755 "$out/etc/pacman.d"
        # install -m 644 "archlinux/PKGBUILD-qubes-pacman-options.conf" "$out/etc/pacman.d/10-qubes-options.conf"

        # remove the default VMExec definition since we need to modify it's PATH based on user args in the updates module
        rm "$out/etc/qubes-rpc/qubes.VMExec"
        # also remove VMExecGUI since it points to VMExec and will be a dangling link
        rm "$out/etc/qubes-rpc/qubes.VMExecGUI"

        mv "$out/usr/bin/qubes-vmexec" "$out/bin/"
        mv "$out/usr/share" "$out/share"
        mv "$out/etc/systemd/system/xendriverdomain.service" "$out/lib/systemd/system/"

        rm -rf "$out/usr/bin"
        rm -rf "$out/var/run"
      ''
      + lib.optionalString (!enableNetworking) ''
        # mock update-proxy-configs with an empty script
        echo "#!${bash}/bin/sh" > "$out/lib/qubes/update-proxy-configs"
        chmod +x "$out/lib/qubes/update-proxy-configs"
      ''
      + lib.optionalString enableNetworking ''
        make -C network install \
            PYTHON_PREFIX_ARG="--prefix ." \
            DESTDIR="$out" \
            BINDIR=/bin \
            SBINDIR=/bin \
            LIBDIR=/lib \
            SYSLIBDIR=/lib \
            SYSTEM_DROPIN_DIR=/usr/lib/systemd/system \
            USER_DROPIN_DIR=/usr/lib/systemd/user \
            DIST=nixos
        make install-netvm \
            PYTHON_PREFIX_ARG="--prefix ." \
            DESTDIR="$out" \
            BINDIR=/bin \
            SBINDIR=/bin \
            LIBDIR=/lib \
            SYSLIBDIR=/lib \
            SYSTEM_DROPIN_DIR=/usr/lib/systemd/system \
            USER_DROPIN_DIR=/usr/lib/systemd/user \
            DIST=nixos

        # overwrite the broken symlink created by make install-netvm
        ln -sf ../../lib/qubes/qubes-setup-dnat-to-ns $out/etc/dhclient.d/qubes-setup-dnat-to-ns.sh

        for path in lib/qubes/init/network-uplink-wait.sh lib/qubes/setup-ip lib/qubes/update-proxy-configs ; do
          substituteInPlace "$out/$path" --replace '/usr/lib/qubes/init/functions' "functions"
        done

        cat >> "$out/lib/qubes/update-proxy-configs" <<EOT

        # NixOS
        if [ -d /run/current-system ]; then
            NIX_DAEMON_DROPIN=/run/systemd/system/nix-daemon.service.d/override.conf
            UPDATE_CHECK_DROPIN=/run/systemd/system/qubes-update-check.service.d/override.conf

            if [ -n "\$PROXY_ADDR" ]; then
                mkdir -p "\$(dirname "\$NIX_DAEMON_DROPIN")" "\$(dirname "\$UPDATE_CHECK_DROPIN")"
                cat > "\$NIX_DAEMON_DROPIN" <<EOF
        # This file is automatically generated by Qubes (\$0 script).
        # All modifications here will be lost.
        [Service]
        Environment="http_proxy=\$PROXY_ADDR" "https_proxy=\$PROXY_ADDR" "all_proxy=\$PROXY_ADDR"
        Environment="HTTP_PROXY=\$PROXY_ADDR" "HTTPS_PROXY=\$PROXY_ADDR" "ALL_PROXY=\$PROXY_ADDR"
        Environment="no_proxy=127.0.0.1,localhost" "NO_PROXY=127.0.0.1,localhost"
        EOF

                # Flake inputs are fetched by the client, not always by nix-daemon.
                cp "\$NIX_DAEMON_DROPIN" "\$UPDATE_CHECK_DROPIN"
            else
                rm -f "\$NIX_DAEMON_DROPIN" "\$UPDATE_CHECK_DROPIN"
            fi

            systemctl daemon-reload
            systemctl try-restart nix-daemon
        fi
        EOT

        substituteInPlace "$out/etc/udev/rules.d/99-qubes-network.rules" --replace '/usr/bin/systemctl' '${systemd}/bin/systemctl'

        mv "$out/etc/udev/rules.d/99-qubes-network.rules" "$out/lib/udev/rules.d/"
      '';

    solutions = {
      default = {
        scripts =
          scripts
          ++ lib.optional enableNetworking "lib/qubes/init/network-uplink-wait.sh"
          ++ lib.optional enableNetworking "lib/qubes/setup-ip";
        interpreter = "none";
        fake.external =
          # guarded by check for /sys/fs/selinux
          ["chcon" "restorecon"]
          # guarded by check for
          ++ ["kdialog"]
          ++ lib.optional (!enableNetworking) "ip";
        fix = {
          "/bin/bash" = true;
          "/usr/bin/qubes-vmexec" = true;
          "/usr/bin/qubesdb-read" = true;
          "/usr/lib/qubes/init/bind-dirs.sh" = true;
          "/usr/lib/qubes/init/setup-rw.sh" = true;
          "/usr/lib/qubes/init/setup-rwdev.sh" = true;
          "/usr/lib/qubes/qrexec-client-vm" = true;
          "/usr/lib/qubes/qubes-fs-tree-check" = true;
          "/usr/lib/qubes/qubes-setup-dnat-to-ns" = true;
          "/usr/lib/qubes/qvm_nautilus_bookmark.sh" = true;
          "/usr/lib/qubes/resize-rootfs" = true;
          "/usr/lib/qubes/update-proxy-configs" = true;
          "/lib/systemd/systemd-sysctl" = true;
          "/sbin/ip" = true;
          umount = true;
          mount = true;
        };
        inputs =
          [
            "bin"
            "lib/qubes"
            "lib/qubes/init"
            "${qubes-core-qrexec}/lib/qubes"
            "${systemd}/lib/systemd"
            bash
            coreutils
            diffutils
            e2fsprogs
            findutils
            gawk
            getent
            gnugrep
            gnused
            kmod
            lvm2
            mount
            nettools
            networkmanager
            parted
            procps
            psmisc
            qubes-core-qrexec
            qubes-core-qubesdb
            stdenv.cc.libc
            systemd
            umount
            util-linux
            zenity
          ]
          ++ lib.optional enableNetworking iproute2;
        keep = {
          source = ["$file_name"];
          "$rc" = true;
          # 4.3 mount-dirs.sh uses these as bool-flag commands (`if $mount_home; then`)
          "$mount_home" = true;
          "$mount_usr_local" = true;
          "/rw/config/qubes_ip_change_hook" = enableNetworking;
          "/rw/config/qubes-ip-change-hook" = enableNetworking;
          "/run/wrappers/bin/qfile-unpacker" = true;
        };
        execer =
          [
            "cannot:${e2fsprogs}/bin/fsck.ext4"
            "cannot:${e2fsprogs}/bin/mkfs.ext4"
            "cannot:${kmod}/bin/modprobe"
            "cannot:${lib.getBin lvm2}/bin/dmsetup"
            "cannot:${networkmanager}/bin/nmcli"
            "cannot:${systemd}/bin/systemctl"
            "cannot:${systemd}/bin/udevadm"
            "cannot:bin/qubes-vmexec"
            "cannot:lib/qubes/init/bind-dirs.sh"
            "cannot:lib/qubes/qfile-unpacker"
            "cannot:${qubes-core-qrexec}/lib/qubes/qrexec-client-vm"
            "cannot:${qubes-core-qrexec}/bin/qrexec-client-vm"
            "cannot:${zenity}/bin/zenity"
          ]
          ++ lib.optional enableNetworking "cannot:${iproute2}/bin/ip";
      };
    };

    dontWrapGApps = true;

    preFixup = ''
      makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
    '';

    postFixup = ''
      # The Python setup hook does not treat this plain mkDerivation as a
      # Python package, so make its import path explicit in every generated
      # wrapper.  This includes both qubesagent from this output and the
      # qubesdb extension from its own package.
      makeWrapperArgs+=(
        --prefix PYTHONPATH : "$out/${python3.sitePackages}:${pythonProgramPath}"
      )
      wrapPythonProgramsIn "$out/bin" ""
      wrapPythonProgramsIn "$out/etc/qubes-rpc" ""
    '';

    meta = {
      description = "The Qubes core files for installation inside a Qubes VM";
      homepage = "https://qubes-os.org";
      license = lib.licenses.gpl2Plus;
      maintainers = [];
      platforms = lib.platforms.linux;
    };
  })
