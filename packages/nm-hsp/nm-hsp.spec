Name:           nm-hsp
Version:        %{nm_hsp_version}
Release:        1.hsp
Summary:        Friendly NetworkManager terminal interface from Home Server Project
License:        Apache-2.0
URL:            https://github.com/home-server-project/nm-hsp
Source0:        nm-hsp-payload.tar.gz
BuildArch:      %{rpm_arch}
Requires:       NetworkManager
Requires:       polkit

%description
NetworkManager-HSP (nm-hsp) is a friendly terminal interface for ordinary
Ethernet, Wi-Fi, and NetworkManager troubleshooting on headless and
appliance-style Linux systems.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%{_bindir}/nm-hsp
%license %{_licensedir}/nm-hsp/LICENSE
%doc %{_docdir}/nm-hsp/README.md
%{_datadir}/polkit-1/rules.d/49-nm-hsp-vpn.rules
