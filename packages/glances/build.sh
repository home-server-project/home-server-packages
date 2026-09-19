#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/glances"
OUT_DIR="${ROOT_DIR}/out/glances"
SRC_DIR="${ROOT_DIR}/.work/glances"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-glances"
PAYLOAD_DIR="${ROOT_DIR}/.work/glances-payload"
PRIVATE_DIR="${PAYLOAD_DIR}/usr/libexec/glances/python"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}"
mkdir -p \
    "${SRC_DIR}" \
    "${OUT_DIR}/rpms" \
    "${OUT_DIR}/source" \
    "${OUT_DIR}/licenses" \
    "${OUT_DIR}/metadata" \
    "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    "${PRIVATE_DIR}" \
    "${PAYLOAD_DIR}/usr/share/licenses/glances" \
    "${PAYLOAD_DIR}/usr/share/doc/glances"

git clone --filter=blob:none --no-checkout "${GLANCES_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/v${GLANCES_VERSION}:refs/tags/v${GLANCES_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/v${GLANCES_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${GLANCES_COMMIT}" ]]; then
    echo "ERROR: Glances tag v${GLANCES_VERSION} resolves to ${TAG_COMMIT}, expected ${GLANCES_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${GLANCES_COMMIT}"

test -f COPYING
test -f README.rst
test -f pyproject.toml
test -d glances/outputs/static

GLANCES_EXPECTED_VERSION="${GLANCES_VERSION}" python3 - <<'PY'
import os
import tomllib
from pathlib import Path

with Path("pyproject.toml").open("rb") as fh:
    project = tomllib.load(fh)["project"]

if project.get("name") != "Glances":
    raise SystemExit(f"Unexpected project name: {project.get('name')!r}")
if project.get("license") != "LGPL-3.0-only":
    raise SystemExit(f"Unexpected Glances license: {project.get('license')!r}")

version_text = Path("glances/__init__.py").read_text()
expected = os.environ["GLANCES_EXPECTED_VERSION"]
if expected not in version_text:
    raise SystemExit(f"Glances source does not contain expected version {expected}")
PY

# Glances is pure Python and its tagged source already contains the built WebUI.
# Copy the exact verified application tree directly; runtime libraries remain
# distro packages.
cp -a glances "${PRIVATE_DIR}/glances"
find "${PRIVATE_DIR}" -type d -name __pycache__ -prune -exec rm -rf {} +
find "${PRIVATE_DIR}" -type f -name '*.pyc' -delete

PYTHONPATH="${PRIVATE_DIR}" EXPECTED_GLANCES="${GLANCES_VERSION}" python3 - <<'PY'
import os
import glances

version = glances.__version__
print("Glances", version)
assert version == os.environ["EXPECTED_GLANCES"]
assert callable(glances.main)
PY

# Glances itself should remain architecture-independent. Native runtime modules
# such as psutil come from AlmaLinux/EPEL and are not copied into this payload.
if find "${PRIVATE_DIR}" -type f -print0 | xargs -0 file | grep -q 'ELF'; then
    echo "ERROR: private Glances application payload contains an ELF file" >&2
    exit 1
fi

install -Dm0644 COPYING "${PAYLOAD_DIR}/usr/share/licenses/glances/COPYING"
install -Dm0644 README.rst "${PAYLOAD_DIR}/usr/share/doc/glances/README.rst"

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/glances-payload.tar.gz" .
cp "${PKG_DIR}/glances.spec" "${RPMBUILD_DIR}/SPECS/glances.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "glances_version ${GLANCES_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/glances.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'glances-*.noarch.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'glances-*.noarch.rpm' -print -quit)"

# Retain the exact upstream source and Home Server Project packaging recipe with
# the published binary artifact.
git archive --format=tar.gz --prefix="glances-${GLANCES_VERSION}/" \
    -o "${OUT_DIR}/source/glances-${GLANCES_VERSION}-${GLANCES_COMMIT}.tar.gz" \
    "${GLANCES_COMMIT}"
cp "${PKG_DIR}/glances.spec" "${OUT_DIR}/source/glances.spec"
cp "${PKG_DIR}/package.env" "${OUT_DIR}/source/package.env"
install -Dm0644 COPYING "${OUT_DIR}/licenses/COPYING"

cat > "${OUT_DIR}/metadata/package.env" <<EOF_META
PACKAGE=glances
VERSION=${GLANCES_VERSION}
UPSTREAM_COMMIT=${GLANCES_COMMIT}
LICENSE=${GLANCES_LICENSE}
UPSTREAM=${GLANCES_UPSTREAM}
PACKAGE_CHANNEL=el10-noarch
EOF_META

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/* > metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
rpm -qp --qf '%{ARCH}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-arch.txt"
rpm -qp --qf '%{SIZE}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-installed-size.txt"

# Package/compliance gates.
grep -Fqx 'noarch' "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/glances$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/libexec/glances/python/glances/' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/libexec/glances/python/glances/outputs/static/' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/glances/COPYING$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/glances/README.rst$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: LGPL-3.0-only$' "${OUT_DIR}/metadata/rpm-info.txt"
for dep in \
    python3 \
    python3-dateutil \
    python3-defusedxml \
    python3-podman \
    python3-fastapi \
    python3-jinja2 \
    python3-packaging \
    python3-psutil \
    python3-requests \
    python3-shtab \
    python3-uvicorn; do
    grep -Fq "${dep}" "${OUT_DIR}/metadata/rpm-requires.txt"
done

printf 'Built Glances %s AlmaLinux 10 noarch RPM from %s\n' \
    "${GLANCES_VERSION}" "${GLANCES_COMMIT}"
