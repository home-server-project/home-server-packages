# nm-hsp package

Home Server Project RPM packaging for [NetworkManager-HSP](https://github.com/home-server-project/nm-hsp).

The package is built from one exact source commit and published as a single architecture-neutral OCI package artifact containing both:

- x86_64 RPM
- aarch64 RPM

Each architecture is built and validated independently on Fedora 44 and AlmaLinux 10 before the shared `:stable` package artifact is published.

The installed command is:

`/usr/bin/nm-hsp`

NetworkManager remains the backend. The package does not replace `nmcli` or `nmtui`; products may present nm-hsp as the friendly interface while retaining the native NetworkManager tools as advanced fallbacks.


For nm-hsp 0.2.0 and later, the RPM also installs the packaged VPN service authorization rule at:

`/usr/share/polkit-1/rules.d/49-nm-hsp-vpn.rules`

The rule permits normal-user runtime start/stop control only for the supported Tailscale and NetBird systemd services; nm-hsp does not change their boot enablement.
