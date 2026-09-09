Name:           cockpit-upside
Version:        %{upside_version}
Release:        1.hsp
Summary:        UPS monitoring for Cockpit, powered by NUT
License:        LGPL-2.1-or-later
URL:            https://github.com/deviationist/cockpit-upside
Source0:        cockpit-upside-payload.tar.gz

BuildArch:      noarch
BuildRequires:  tar
Requires:       cockpit-bridge

%description
UPSide is a Cockpit frontend for Network UPS Tools (NUT).

This Home Server Project package contains a pre-built static UPSide bundle from
an exact verified upstream release and commit. The same RPM is validated on
Fedora and Enterprise Linux before publication.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%{_datadir}/cockpit/upside/
%{_datadir}/metainfo/io.github.deviationist.upside.metainfo.xml
%{_docdir}/cockpit-upside/README.md
%license %{_licensedir}/cockpit-upside/LICENSE
%license %{_licensedir}/cockpit-upside/index.js.LEGAL.txt
