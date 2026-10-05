%global debug_package %{nil}

Name:           python3-docker
Version:        %{python_docker_version}
Release:        1.hsp%{?dist}
Summary:        Python library for the Docker Engine API
License:        Apache-2.0
URL:            https://github.com/docker/docker-py
Source0:        docker-py-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros
BuildRequires:  python3-hatchling
BuildRequires:  python3-hatch-vcs

Requires:       python3-requests >= 2.26.0
Requires:       python3-urllib3 >= 1.26.0

%description
Docker SDK for Python provides a Python API for the Docker Engine.

This Home Server Project package is built independently for Fedora 44 and
AlmaLinux 10 from the same exact verified upstream source. Runtime Python
libraries are provided by the target distribution and are not bundled.

%prep
%autosetup -n docker-py-%{version}

%build
export SETUPTOOLS_SCM_PRETEND_VERSION=%{version}
%pyproject_wheel

%install
%pyproject_install
%pyproject_save_files docker

%check
# Docker SDK ships Windows-only named-pipe modules and an optional SSH module.
# Check the installed Linux top-level package here; clean target validation below
# separately verifies the installed RPM and its distro-provided dependencies.
%pyproject_check_import -t
PYTHONPATH=%{buildroot}%{python3_sitelib} python3 - <<'PY'
import docker

assert docker.__version__ == "%{version}"
assert docker.DockerClient is not None
assert callable(docker.from_env)
assert docker.APIClient is not None
PY

%files -f %{pyproject_files}
%license LICENSE
%doc README.md
