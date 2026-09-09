#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/cockpit-upside"
OUT_DIR="${ROOT_DIR}/out/cockpit-upside"
SRC_DIR="${ROOT_DIR}/.work/cockpit-upside"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}"
mkdir -p "${SRC_DIR}" "${OUT_DIR}/rpms" "${OUT_DIR}/source" "${OUT_DIR}/licenses" "${OUT_DIR}/metadata"

git clone --filter=blob:none --no-checkout "${UPSIDE_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/${UPSIDE_VERSION}:refs/tags/${UPSIDE_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/${UPSIDE_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${UPSIDE_COMMIT}" ]]; then
    echo "ERROR: UPSide tag ${UPSIDE_VERSION} resolves to ${TAG_COMMIT}, expected ${UPSIDE_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${UPSIDE_COMMIT}"

# Build through upstream's own RPM target. This intentionally lets the upstream
# spec choose distro-specific behavior (for example Fedora bundle rebuilding).
make rpm

find . -maxdepth 1 -type f -name 'cockpit-upside-*.noarch.rpm' -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'cockpit-upside-*.noarch.rpm' -print -quit)"

# Retain the exact upstream-generated source inputs used by rpmbuild. These
# include the source/dist archive and, when upstream creates it, the locked npm
# module cache used for Fedora bundle rebuilding.
find . -maxdepth 1 -type f \
    \( -name 'cockpit-upside-*.tar.xz' -o -name 'cockpit-upside.spec' \) \
    -exec cp -v {} "${OUT_DIR}/source/" \;

# Also retain a plain archive of the exact pinned upstream commit. This gives a
# simple source snapshot independent of generated build artifacts.
git archive --format=tar.gz --prefix="cockpit-upside-${UPSIDE_VERSION}/" \
    -o "${OUT_DIR}/source/cockpit-upside-${UPSIDE_VERSION}-${UPSIDE_COMMIT}.tar.gz" \
    "${UPSIDE_COMMIT}"

install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"
test -f dist/index.js.LEGAL.txt
install -Dm0644 dist/index.js.LEGAL.txt "${OUT_DIR}/licenses/index.js.LEGAL.txt"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=cockpit-upside
VERSION=${UPSIDE_VERSION}
UPSTREAM_COMMIT=${UPSIDE_COMMIT}
LICENSE=${UPSIDE_LICENSE}
UPSTREAM=${UPSIDE_UPSTREAM}
EOF

sha256sum "${OUT_DIR}"/rpms/* "${OUT_DIR}"/source/* "${OUT_DIR}"/licenses/* \
    > "${OUT_DIR}/metadata/SHA256SUMS"

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"

# License/compliance gates.
grep -q '/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/index.js.LEGAL.txt$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: LGPL-2.1-or-later$' "${OUT_DIR}/metadata/rpm-info.txt"
grep -q 'cockpit-bridge' "${OUT_DIR}/metadata/rpm-requires.txt"
test -n "$(find "${OUT_DIR}/source" -maxdepth 1 -type f -name 'cockpit-upside-*.tar.xz' -print -quit)"

printf 'Built and validated cockpit-upside %s from %s\n' "${UPSIDE_VERSION}" "${UPSIDE_COMMIT}"
