%global debug_package %{nil}

Name:           virtui-manager
Version:        %{virtui_version}
Release:        1.hsp
Summary:        Terminal-based interface for managing libvirt virtual machines
License:        GPL-3.0-or-later
URL:            https://github.com/aginies/virtui-manager
Source0:        virtui-manager-payload.tar.gz

BuildArch:      noarch
AutoReqProv:    no

Requires:       bash
Requires:       python3
Requires:       python3-libvirt
Requires:       python3-pyyaml
Requires:       python3-requests
Requires:       python3-netifaces
Requires:       python3-gobject
Requires:       python3-packaging
Requires:       libosinfo
Requires:       osinfo-db
Requires:       tmux
Requires:       7zip
Requires:       novnc
Requires:       python3-websockify

%description
VirtUI Manager is a terminal-based interface for managing QEMU/KVM virtual
machines through libvirt.

This Home Server Project package contains the upstream Python application and a
locked private Textual dependency tree under /usr/libexec/virtui-manager. Native
libvirt, GObject, network and operating-system integrations remain provided by
the host distribution.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

mkdir -p %{buildroot}%{_bindir}

cat > %{buildroot}%{_bindir}/virtui-manager <<'EOF_WRAPPER'
#!/usr/bin/bash
export PYTHONPATH="/usr/libexec/virtui-manager/python${PYTHONPATH:+:${PYTHONPATH}}"
exec /usr/bin/python3 -c 'from vmanager.wrapper import main; main()' "$@"
EOF_WRAPPER
chmod 0755 %{buildroot}%{_bindir}/virtui-manager

cat > %{buildroot}%{_bindir}/vmc <<'EOF_WRAPPER'
#!/usr/bin/bash
export PYTHONPATH="/usr/libexec/virtui-manager/python${PYTHONPATH:+:${PYTHONPATH}}"
exec /usr/bin/python3 -c 'from vmanager.wrapper import cmd_main; cmd_main()' "$@"
EOF_WRAPPER
chmod 0755 %{buildroot}%{_bindir}/vmc

ln -s vmc %{buildroot}%{_bindir}/virtui-manager-cmd

%files
%license %{_licensedir}/virtui-manager/LICENSE
%license %{_licensedir}/virtui-manager/python/
%doc %{_docdir}/virtui-manager/README.md
%{_bindir}/virtui-manager
%{_bindir}/virtui-manager-cmd
%{_bindir}/vmc
%{_libexecdir}/virtui-manager/
