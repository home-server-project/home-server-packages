#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/superfile"
OUT_DIR="${ROOT_DIR}/out/superfile"
SRC_DIR="${ROOT_DIR}/.work/superfile"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-superfile"
PAYLOAD_DIR="${ROOT_DIR}/.work/superfile-payload"
PATCH_FILE="${PKG_DIR}/patches/0001-backport-linux-cross-filesystem-trash-fix.patch"
PATCH_UPSTREAM_COMMIT="200a0b134574924e1c386996e1aba523a6992ab8"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}"
mkdir -p \
    "${SRC_DIR}" \
    "${OUT_DIR}/rpms" \
    "${OUT_DIR}/source" \
    "${OUT_DIR}/licenses" \
    "${OUT_DIR}/metadata" \
    "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

git clone --filter=blob:none --no-checkout "${SUPERFILE_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/v${SUPERFILE_VERSION}:refs/tags/v${SUPERFILE_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/v${SUPERFILE_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${SUPERFILE_COMMIT}" ]]; then
    echo "ERROR: Superfile tag v${SUPERFILE_VERSION} resolves to ${TAG_COMMIT}, expected ${SUPERFILE_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${SUPERFILE_COMMIT}"

test -f LICENSE
test -f NOTICE.md
test -f README.md
test -f go.mod
test -f go.sum
test -f "${PATCH_FILE}"

# Backport upstream fix for Linux trash operations across filesystems.
# Once a future release already contains this change, this patch must be removed
# rather than silently skipped.
git apply --check "${PATCH_FILE}"
git apply "${PATCH_FILE}"

export GOTOOLCHAIN=auto

go env GOVERSION > "${OUT_DIR}/metadata/go-version.txt"
go mod verify
go test ./...

# Use upstream's Linux build path. It builds with CGO_ENABLED=0.
bash ./build.sh

test -x ./bin/spf
./bin/spf --version | tee "${OUT_DIR}/metadata/spf-version.txt"
grep -Fq "v${SUPERFILE_VERSION}" "${OUT_DIR}/metadata/spf-version.txt"

# A CGO-disabled Go build should not depend on a dynamic ELF interpreter.
if readelf -l ./bin/spf | grep -q 'Requesting program interpreter'; then
    echo "ERROR: Superfile binary unexpectedly requires a dynamic ELF interpreter" >&2
    exit 1
fi

mkdir -p \
    "${PAYLOAD_DIR}/usr/bin" \
    "${PAYLOAD_DIR}/usr/share/licenses/superfile" \
    "${PAYLOAD_DIR}/usr/share/doc/superfile"

install -Dm0755 ./bin/spf "${PAYLOAD_DIR}/usr/bin/spf"
install -Dm0644 LICENSE "${PAYLOAD_DIR}/usr/share/licenses/superfile/LICENSE"
install -Dm0644 NOTICE.md "${PAYLOAD_DIR}/usr/share/licenses/superfile/NOTICE.md"
install -Dm0644 README.md "${PAYLOAD_DIR}/usr/share/doc/superfile/README.md"

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/superfile-payload.tar.gz" .
cp "${PKG_DIR}/superfile.spec" "${RPMBUILD_DIR}/SPECS/superfile.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "superfile_version ${SUPERFILE_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/superfile.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'superfile-*.x86_64.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'superfile-*.x86_64.rpm' -print -quit)"

# Retain the exact upstream source, our packaging recipe, and the applied
# upstream backport with the binary artifact.
git archive --format=tar.gz --prefix="superfile-${SUPERFILE_VERSION}/" \
    -o "${OUT_DIR}/source/superfile-${SUPERFILE_VERSION}-${SUPERFILE_COMMIT}.tar.gz" \
    "${SUPERFILE_COMMIT}"
cp "${PKG_DIR}/superfile.spec" "${OUT_DIR}/source/superfile.spec"
install -Dm0644 "${PATCH_FILE}" \
    "${OUT_DIR}/source/0001-backport-linux-cross-filesystem-trash-fix.patch"

install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"
install -Dm0644 NOTICE.md "${OUT_DIR}/licenses/NOTICE.md"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=superfile
VERSION=${SUPERFILE_VERSION}
UPSTREAM_COMMIT=${SUPERFILE_COMMIT}
LICENSE=${SUPERFILE_LICENSE}
UPSTREAM=${SUPERFILE_UPSTREAM}
PACKAGE_CHANNEL=universal-x86_64
BACKPORT_1_UPSTREAM_COMMIT=${PATCH_UPSTREAM_COMMIT}
BACKPORT_1_FILE=0001-backport-linux-cross-filesystem-trash-fix.patch
EOF

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/* > metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
rpm -qp --qf '%{ARCH}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-arch.txt"

# Package and license/compliance gates.
grep -q '^x86_64$' "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/spf$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/superfile/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/superfile/NOTICE.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/superfile/README.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: MIT$' "${OUT_DIR}/metadata/rpm-info.txt"

printf 'Built Superfile %s RPM from %s with upstream backport %s\n' \
    "${SUPERFILE_VERSION}" "${SUPERFILE_COMMIT}" "${PATCH_UPSTREAM_COMMIT}"
