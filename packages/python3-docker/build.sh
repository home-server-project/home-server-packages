#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/python3-docker"
TARGET="${HSP_TARGET:-}"
OUT_DIR="${ROOT_DIR}/out/python3-docker/${TARGET}"
SRC_DIR="${ROOT_DIR}/.work/python3-docker-${TARGET}"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-python3-docker-${TARGET}"

source "${PKG_DIR}/package.env"

case "${TARGET}" in
    fedora44)
        EXPECTED_DIST=".fc44"
        ;;
    el10)
        EXPECTED_DIST=".el10"
        ;;
    *)
        echo "ERROR: HSP_TARGET must be fedora44 or el10" >&2
        exit 1
        ;;
esac

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}"
mkdir -p     "${SRC_DIR}"     "${OUT_DIR}/rpms"     "${OUT_DIR}/source"     "${OUT_DIR}/licenses"     "${OUT_DIR}/metadata"     "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

git clone --filter=blob:none --no-checkout "${PYTHON_DOCKER_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin     "refs/tags/${PYTHON_DOCKER_VERSION}:refs/tags/${PYTHON_DOCKER_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/${PYTHON_DOCKER_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${PYTHON_DOCKER_COMMIT}" ]]; then
    echo "ERROR: docker-py tag ${PYTHON_DOCKER_VERSION} resolves to ${TAG_COMMIT}, expected ${PYTHON_DOCKER_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${PYTHON_DOCKER_COMMIT}"

test -f LICENSE
test -f README.md
test -f pyproject.toml
test -d docker

PYTHON_DOCKER_EXPECTED_VERSION="${PYTHON_DOCKER_VERSION}" python3 - <<'PY'
import os
import tomllib
from pathlib import Path

with Path("pyproject.toml").open("rb") as fh:
    project = tomllib.load(fh)["project"]

if project.get("name") != "docker":
    raise SystemExit(f"Unexpected project name: {project.get('name')!r}")
if project.get("license") != "Apache-2.0":
    raise SystemExit(f"Unexpected docker-py license: {project.get('license')!r}")
if "version" not in project.get("dynamic", []):
    raise SystemExit("docker-py no longer declares a dynamic version")

deps = project.get("dependencies", [])
if not any(dep.lower().startswith("requests ") or dep.lower().startswith("requests>") for dep in deps):
    raise SystemExit("docker-py no longer declares Requests")
if not any(dep.lower().startswith("urllib3 ") or dep.lower().startswith("urllib3>") for dep in deps):
    raise SystemExit("docker-py no longer declares urllib3")

expected = os.environ["PYTHON_DOCKER_EXPECTED_VERSION"]
if not expected:
    raise SystemExit("Expected docker-py version is empty")
PY

git archive     --format=tar.gz     --prefix="docker-py-${PYTHON_DOCKER_VERSION}/"     -o "${RPMBUILD_DIR}/SOURCES/docker-py-${PYTHON_DOCKER_VERSION}.tar.gz"     "${PYTHON_DOCKER_COMMIT}"

cp "${PKG_DIR}/python3-docker.spec" "${RPMBUILD_DIR}/SPECS/python3-docker.spec"

rpmbuild -bb     --define "_topdir ${RPMBUILD_DIR}"     --define "python_docker_version ${PYTHON_DOCKER_VERSION}"     "${RPMBUILD_DIR}/SPECS/python3-docker.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'python3-docker-*.noarch.rpm'     -exec cp -v {} "${OUT_DIR}/rpms/" \;

RPM_FILE="$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'python3-docker-*.noarch.rpm' -print -quit)"
test -n "${RPM_FILE}"

RPM_RELEASE="$(rpm -qp --qf '%{RELEASE}' "${RPM_FILE}")"
if [[ "${RPM_RELEASE}" != *"${EXPECTED_DIST}" ]]; then
    echo "ERROR: RPM release ${RPM_RELEASE} does not match target ${EXPECTED_DIST}" >&2
    exit 1
fi

cp "${RPMBUILD_DIR}/SOURCES/docker-py-${PYTHON_DOCKER_VERSION}.tar.gz"    "${OUT_DIR}/source/docker-py-${PYTHON_DOCKER_VERSION}-${PYTHON_DOCKER_COMMIT}.tar.gz"
cp "${PKG_DIR}/python3-docker.spec" "${OUT_DIR}/source/python3-docker.spec"
cp "${PKG_DIR}/package.env" "${OUT_DIR}/source/package.env"
install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"

cat > "${OUT_DIR}/metadata/package.env" <<EOF_META
PACKAGE=python3-docker
VERSION=${PYTHON_DOCKER_VERSION}
UPSTREAM_COMMIT=${PYTHON_DOCKER_COMMIT}
LICENSE=${PYTHON_DOCKER_LICENSE}
UPSTREAM=${PYTHON_DOCKER_UPSTREAM}
PACKAGE_CHANNEL=${TARGET}-noarch
TARGET=${TARGET}
EOF_META

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/* > metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

rpm -qpl "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-info.txt"
rpm -qp --qf '%{ARCH}\n' "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-arch.txt"
rpm -qp --qf '%{SIZE}\n' "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-installed-size.txt"
rpm -qp --qf '%{RELEASE}\n' "${RPM_FILE}" > "${OUT_DIR}/metadata/rpm-release.txt"

grep -Fqx 'noarch' "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/site-packages/docker/__init__.py$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/site-packages/docker/version.py$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/site-packages/docker-.*\.dist-info/METADATA$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/python3-docker/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/python3-docker/README.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: Apache-2.0$' "${OUT_DIR}/metadata/rpm-info.txt"
grep -Fq 'python3-requests >= 2.26.0' "${OUT_DIR}/metadata/rpm-requires.txt"
grep -Fq 'python3-urllib3 >= 1.26.0' "${OUT_DIR}/metadata/rpm-requires.txt"

printf 'Built python3-docker %s for %s from %s\n'     "${PYTHON_DOCKER_VERSION}" "${TARGET}" "${PYTHON_DOCKER_COMMIT}"
