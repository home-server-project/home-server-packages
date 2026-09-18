Name:           mergerfs
Version:        %{mergerfs_version}
Release:        1.hsp
Summary:        Featureful FUSE based union filesystem
License:        ISC
URL:            https://github.com/trapexit/mergerfs
Source0:        mergerfs-payload.tar.gz

%description
mergerfs is a union filesystem geared toward simplifying storage and
management of files across numerous commodity storage devices.

This Home Server Project package contains the AlmaLinux 10 x86-64-v2 mergerfs
payload built from an exact verified upstream release and commit.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%{_bindir}/mergerfs
%{_bindir}/mergerfs-fusermount
%{_bindir}/fsck.mergerfs
%{_bindir}/mergerfs.collect-info
/sbin/mount.mergerfs
/usr/lib/mergerfs/preload.so
%{_mandir}/man1/mergerfs.1*
%license %{_licensedir}/mergerfs/LICENSE
%doc %{_docdir}/mergerfs/README.md
