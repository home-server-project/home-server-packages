Name:           superfile
Version:        %{superfile_version}
Release:        1.hsp
Summary:        Modern terminal file manager
License:        MIT
URL:            https://github.com/yorukot/superfile
Source0:        superfile-payload.tar.gz

%description
Superfile is a modern terminal file manager.

This Home Server Project package contains the Linux x86_64 Superfile binary
built from an exact verified upstream release and commit. The same RPM is
validated on Fedora and Enterprise Linux before publication.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%{_bindir}/spf
%license %{_licensedir}/superfile/LICENSE
%license %{_licensedir}/superfile/NOTICE.md
%doc %{_docdir}/superfile/README.md
