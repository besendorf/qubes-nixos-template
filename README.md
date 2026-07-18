# nix expressions for creating a qubes templatevm

## getting started

*warning*: proceed at your own risk, this involves copying files to dom0 and installing a template
without gpg signature verification

1. download the template rpm from github releases or build it yourself via `nix build .#rpm` ( preferred )
2. copy the template rpm to dom0
```
qvm-run --pass-io <YOUR_DOWNLOAD_VM> 'cat <FULL_RPM_PATH>' > qubes-template-nixos-4.3.0-unavailable.noarch.rpm
```
3. install the template
```
qvm-template install qubes-template-nixos-4.3.0-unavailable.noarch.rpm --nogpgcheck
```
4. start the template and wait about 30s ( see qrexec notes. )
```
qvm-start nixos
```
5. start a terminal in the template
```
qvm-run nixos xterm
```

at this point you can customize the template and use it like any other NixOS install. the example config has been copied to `/etc/nixos`.

## alternative install via iso

for those that want to avoid installing anything in dom0, these instructions will allow you to install to
a fresh hvm template.

1. download the custom installer iso from github releases
2. create a new qube, select type "TemplateVM", template "(none)", name "nixos", networking "(none)", tick "Launch settings after creation", press "OK" button
3. in the settings for the new qube, go to the advanced tab, change the kernel to "(provided by qube)" and virtualization mode to "HVM", press "Apply" button
4. click the "boot qube from CD-ROM" button, click the "from file in qube" option and browse for the downloaded iso. press "OK" button, the qube will launch a boot console
5. wait for the installer to display its target disk, then type the full device path shown to confirm that the disk may be erased
6. the system will auto shutdown on successful install
7. open the settings for the qube, go to the advanced tab, change the kernel to "default (...)" and virtualization mode to "default (PVH)"
8. start the template and wait about 30s ( see qrexec notes. )
```
qvm-start nixos
```
9. start a terminal in the template
```
qvm-run nixos xterm
```

## qubes updates proxy

by default a qubes template does not have direct internet access and instead uses the qubes updates proxy
over qrpc. leave the template's networking set to "none"; Qubes forwards connections to
`127.0.0.1:8082` to the UpdateVM selected by the `qubes.UpdatesProxy` policy in dom0.

the template automatically supplies this proxy to the nix daemon, nix commands (including legacy
commands such as `nix-shell`), `sudo nix`, `nixos-rebuild`, and Qubes-triggered update checks. an
explicit proxy set by the caller takes precedence. app qubes do not enable the Qubes updates proxy
by default, so the wrappers leave their environment unchanged and normal NetVM networking continues
to work.

if downloads fail, first check that the local forwarder and the Qubes service marker are available:
```
systemctl status qubes-updates-proxy-forwarder.socket
test -e /run/qubes-service/updates-proxy-setup
curl --proxy http://127.0.0.1:8082/ https://cache.nixos.org/
```
if the curl command fails, check the `qubes.UpdatesProxy` policy and its target UpdateVM in dom0.

## application menus

New template RPMs select `Qubes Run Terminal` and `XTerm` by default. To make
applications installed later available, open the qube's **Settings**, select
**Applications**, and use **Refresh Applications**. Move the applications you
want to the shown list and apply the change.

The equivalent command-line refresh must be run in dom0:

```console
qvm-sync-appmenus <QUBE_NAME>
```

Refresh both the TemplateVM and an existing AppVM after changing the
TemplateVM's installed packages:

```console
qvm-sync-appmenus nixos
qvm-sync-appmenus <APPVM_NAME>
```

Qubes stores the selected application IDs in dom0. Consequently, rebuilding an
already-installed template cannot replace a stale selection left by an older
RPM. Refresh it once and reselect the applications in **Settings**. See the
[Qubes app menu troubleshooting guide](https://doc.qubes-os.org/en/latest/user/troubleshooting/app-menu-shortcut-troubleshooting.html)
for inspecting or replacing the selection with `qvm-appmenus`.

### issues with remote nix configs on github

you may run into issues if you pull a remote nix config over ssh from github. to workaround
you can add the following to `~/.ssh/config` ( the host and port overrides are necessary since these
qubes updates proxy filters port 22. ):
```
Host github.com
  HostName ssh.github.com
  Port 443
  ProxyCommand nc -X connect -x 127.0.0.1:8082 %h %p
```

## notes

### what works
- qrexec eventually works
- appvm networking
- xorg
- copy / paste
- qvm-copy
- ssh over qrexec ( handy for using --target-host with nixos-rebuild )
- memory reporting / ballooning
- qubes update checks
- qubes update triggers ( requires unmerged upstream changes )
- usb proxy
- building an rpm for the templatevm
- update proxy
- application menu discovery, synchronization, and launching

### what doesn't work / untested
- qrexec startup isn't clean, commands can fail initially
- using a non-xen provided kernel
- using as netvm or usbvm
- time sync via rpc ( currently handled is systemd-timesyncd, but per vm ntp sync creates more attack surface area? )
- audio

### bugs
- memory resizing seems to cause crashes in ff

### todo
- deal with substituteInPlace deprecation
- support both qubes 4.2 and 4.3 package sets
