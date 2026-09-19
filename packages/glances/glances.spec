%global debug_package %{nil}

Name:           glances
Version:        %{glances_version}
Release:        1.hsp
Summary:        Cross-platform system monitoring tool
License:        LGPL-3.0-only
URL:            https://github.com/nicolargo/glances
Source0:        glances-payload.tar.gz

BuildArch:      noarch
AutoReqProv:    no

Requires:       python3
Requires:       python3-dateutil
Requires:       python3-defusedxml
Requires:       python3-podman
Requires:       python3-fastapi
Requires:       python3-jinja2
Requires:       python3-packaging
Requires:       python3-psutil
Requires:       python3-requests
Requires:       python3-shtab
Requires:       python3-uvicorn

%description
Glances is a system monitoring application with terminal, WebUI, and REST API
interfaces.

This Home Server Project package contains the exact verified upstream Glances
Python application under /usr/libexec/glances. Runtime Python libraries are
provided by AlmaLinux 10 and EPEL rather than bundled into the RPM.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

mkdir -p %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/glances <<'EOF_WRAPPER'
#!/usr/bin/bash
export PYTHONPATH="/usr/libexec/glances/python${PYTHONPATH:+:${PYTHONPATH}}"
exec /usr/bin/python3 -c 'from glances import main; main()' "$@"
EOF_WRAPPER
chmod 0755 %{buildroot}%{_bindir}/glances

%files
%license %{_licensedir}/glances/COPYING
%doc %{_docdir}/glances/README.rst
%{_bindir}/glances
%{_libexecdir}/glances/
