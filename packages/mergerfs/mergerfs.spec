Name:           mergerfs
Version:        %{mergerfs_version}
Release:        1.hsp%{?dist}
Summary:        Featureful FUSE based union filesystem
License:        ISC
URL:            https://github.com/trapexit/mergerfs
Source0:        mergerfs-%{version}.tar.gz

BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  make
BuildRequires:  libatomic

%global debug_package %{nil}
%undefine _debuginfo_subpackages
%global _enable_debug_packages 0

%description
mergerfs is a union filesystem geared toward simplifying storage and
management of files across numerous commodity storage devices.

%prep
%setup -q

%build
make %{?_smp_mflags} \
    CFLAGS="%{optflags}" \
    CXXFLAGS="%{optflags}" \
    LDFLAGS="%{__global_ldflags}"

%install
make install PREFIX=%{_prefix} DESTDIR=%{buildroot}

%files
%license LICENSE
%doc README.md
/usr/bin/mergerfs
/usr/bin/mergerfs-fusermount
/usr/bin/fsck.mergerfs
/usr/bin/mergerfs.collect-info
/sbin/mount.mergerfs
/usr/lib/mergerfs/preload.so
%{_mandir}/*

%changelog
* Fri Sep 18 2026 Home Server Project <noreply@home-server-project>
- Build mergerfs from verified upstream source for Home Server Project
