#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/cockpit-upside"
OUT_DIR="${ROOT_DIR}/out/cockpit-upside"
SRC_DIR="${ROOT_DIR}/.work/cockpit-upside"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-cockpit-upside"
PAYLOAD_DIR="${ROOT_DIR}/.work/cockpit-upside-payload"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}"
mkdir -p \
    "${SRC_DIR}" \
    "${OUT_DIR}/rpms" \
    "${OUT_DIR}/source" \
    "${OUT_DIR}/licenses" \
    "${OUT_DIR}/metadata" \
    "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

git clone --filter=blob:none --no-checkout "${UPSIDE_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/${UPSIDE_VERSION}:refs/tags/${UPSIDE_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/${UPSIDE_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${UPSIDE_COMMIT}" ]]; then
    echo "ERROR: UPSide tag ${UPSIDE_VERSION} resolves to ${TAG_COMMIT}, expected ${UPSIDE_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${UPSIDE_COMMIT}"

# Build the same static bundle approach already used by Home Server images.
make

test -f dist/manifest.json
test -f dist/index.js.LEGAL.txt

mkdir -p \
    "${PAYLOAD_DIR}/usr/share/cockpit/upside" \
    "${PAYLOAD_DIR}/usr/share/metainfo" \
    "${PAYLOAD_DIR}/usr/share/doc/cockpit-upside" \
    "${PAYLOAD_DIR}/usr/share/licenses/cockpit-upside"

cp -a dist/. "${PAYLOAD_DIR}/usr/share/cockpit/upside/"
cp -a io.github.deviationist.upside.metainfo.xml \
    "${PAYLOAD_DIR}/usr/share/metainfo/io.github.deviationist.upside.metainfo.xml"
install -Dm0644 README.md "${PAYLOAD_DIR}/usr/share/doc/cockpit-upside/README.md"
install -Dm0644 LICENSE "${PAYLOAD_DIR}/usr/share/licenses/cockpit-upside/LICENSE"
install -Dm0644 dist/index.js.LEGAL.txt \
    "${PAYLOAD_DIR}/usr/share/licenses/cockpit-upside/index.js.LEGAL.txt"

# Source maps are development-only and are not shipped by upstream's distro packages.
find "${PAYLOAD_DIR}/usr/share/cockpit/upside" -type f -name '*.map' -delete

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/cockpit-upside-payload.tar.gz" .
cp "${PKG_DIR}/cockpit-upside.spec" "${RPMBUILD_DIR}/SPECS/cockpit-upside.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "upside_version ${UPSIDE_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/cockpit-upside.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'cockpit-upside-*.noarch.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'cockpit-upside-*.noarch.rpm' -print -quit)"

# Retain corresponding upstream source and packaging recipe with the binary artifact.
git archive --format=tar.gz --prefix="cockpit-upside-${UPSIDE_VERSION}/" \
    -o "${OUT_DIR}/source/cockpit-upside-${UPSIDE_VERSION}-${UPSIDE_COMMIT}.tar.gz" \
    "${UPSIDE_COMMIT}"
cp "${PKG_DIR}/cockpit-upside.spec" "${OUT_DIR}/source/cockpit-upside.spec"

install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"
install -Dm0644 dist/index.js.LEGAL.txt "${OUT_DIR}/licenses/index.js.LEGAL.txt"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=cockpit-upside
VERSION=${UPSIDE_VERSION}
UPSTREAM_COMMIT=${UPSIDE_COMMIT}
LICENSE=${UPSIDE_LICENSE}
UPSTREAM=${UPSIDE_UPSTREAM}
PACKAGE_CHANNEL=universal
EOF

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/* > metadata/SHA256SUMS
)

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
(
    cd "${OUT_DIR}"
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

# Package and license/compliance gates.
grep -q '/usr/share/cockpit/upside/manifest.json$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/cockpit-upside/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/cockpit-upside/index.js.LEGAL.txt$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: LGPL-2.1-or-later$' "${OUT_DIR}/metadata/rpm-info.txt"
grep -q 'cockpit-bridge' "${OUT_DIR}/metadata/rpm-requires.txt"

printf 'Built neutral cockpit-upside %s RPM from %s\n' "${UPSIDE_VERSION}" "${UPSIDE_COMMIT}"
