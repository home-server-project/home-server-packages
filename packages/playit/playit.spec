%global debug_package %{nil}

Name:           playit
Version:        %{playit_version}
Release:        1.hsp
Summary:        Game server tunnel agent
License:        BSD-2-Clause
URL:            https://github.com/playit-cloud/playit-agent
Source0:        playit-payload.tar.gz

Requires:       logrotate

%description
Playit makes game servers reachable through the playit.gg tunnel service.

This Home Server Project package contains the Playit CLI and daemon built from
an exact verified upstream release source for AlmaLinux 10 x86_64. The package
ships systemd integration but deliberately does not enable or start the service;
the consuming appliance owns that policy.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%{_bindir}/playit
%{_bindir}/playitd
/opt/playit/agent
/opt/playit/playit
/opt/playit/playitd
/opt/playit/share/init/selected-manager
/opt/playit/share/init/systemd/playit.service
/opt/playit/share/init/openrc/playit
%config(noreplace) %{_sysconfdir}/logrotate.d/playit
%{_unitdir}/playit.service
%{_sysusersdir}/playit.conf
%{_tmpfilesdir}/playit.conf
%license %{_licensedir}/playit/
%doc %{_docdir}/playit/README.md
