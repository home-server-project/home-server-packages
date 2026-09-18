#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/mergerfs"
OUT_DIR="${ROOT_DIR}/out/mergerfs"
SRC_DIR="${ROOT_DIR}/.work/mergerfs"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-mergerfs"
PAYLOAD_DIR="${ROOT_DIR}/.work/mergerfs-payload"
EXPECTED_RPM_ARCH=x86_64_v2

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}"
mkdir -p \
    "${SRC_DIR}" \
    "${OUT_DIR}/rpms" \
    "${OUT_DIR}/source" \
    "${OUT_DIR}/licenses" \
    "${OUT_DIR}/metadata" \
    "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

git clone --filter=blob:none --no-checkout "${MERGERFS_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/${MERGERFS_VERSION}:refs/tags/${MERGERFS_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/${MERGERFS_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${MERGERFS_COMMIT}" ]]; then
    echo "ERROR: mergerfs tag ${MERGERFS_VERSION} resolves to ${TAG_COMMIT}, expected ${MERGERFS_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${MERGERFS_COMMIT}"

test -f LICENSE
test -f README.md
test -f Makefile
test -x buildtools/update-version

./buildtools/update-version

test -f VERSION
test -f src/version.hpp
generated_version="$(cat VERSION)"
if [[ "${generated_version}" != "${MERGERFS_VERSION}" ]]; then
    echo "ERROR: generated mergerfs version is ${generated_version}; expected ${MERGERFS_VERSION}" >&2
    exit 1
fi

glibc_arch="$(rpm -q --qf "%{ARCH}\\n" glibc | head -n1)"
if [[ "${glibc_arch}" != "${EXPECTED_RPM_ARCH}" ]]; then
    echo "ERROR: glibc RPM architecture is ${glibc_arch}; expected ${EXPECTED_RPM_ARCH}" >&2
    exit 1
fi

optflags="$(rpm --eval '%{optflags}')"
ldflags="$(rpm --eval '%{__global_ldflags}')"

make \
    CFLAGS="${optflags}" \
    CXXFLAGS="${optflags}" \
    LDFLAGS="${ldflags}" \
    tests
./build/tests

./build/mergerfs --version | tee "${OUT_DIR}/metadata/mergerfs-version.txt"
grep -Fq "${MERGERFS_VERSION}" "${OUT_DIR}/metadata/mergerfs-version.txt"

make install \
    PREFIX=/usr \
    DESTDIR="${PAYLOAD_DIR}" \
    CFLAGS="${optflags}" \
    CXXFLAGS="${optflags}" \
    LDFLAGS="${ldflags}"

install -Dm0644 LICENSE "${PAYLOAD_DIR}/usr/share/licenses/mergerfs/LICENSE"
install -Dm0644 README.md "${PAYLOAD_DIR}/usr/share/doc/mergerfs/README.md"

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/mergerfs-payload.tar.gz" .
cp "${PKG_DIR}/mergerfs.spec" "${RPMBUILD_DIR}/SPECS/mergerfs.spec"

rpmbuild -bb \
    --target x86_64_v2 \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "mergerfs_version ${MERGERFS_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/mergerfs.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'mergerfs-*.x86_64_v2.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'mergerfs-*.x86_64_v2.rpm' -print -quit)"

git archive --format=tar.gz --prefix="mergerfs-${MERGERFS_VERSION}/" \
    -o "${OUT_DIR}/source/mergerfs-${MERGERFS_VERSION}-${MERGERFS_COMMIT}.tar.gz" \
    "${MERGERFS_COMMIT}"
cp "${PKG_DIR}/mergerfs.spec" "${OUT_DIR}/source/mergerfs.spec"

install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=mergerfs
VERSION=${MERGERFS_VERSION}
UPSTREAM_COMMIT=${MERGERFS_COMMIT}
LICENSE=${MERGERFS_LICENSE}
UPSTREAM=${MERGERFS_UPSTREAM}
PACKAGE_CHANNEL=el10-x86_64_v2
RPM_ARCH=${EXPECTED_RPM_ARCH}
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

grep -Fqx "${EXPECTED_RPM_ARCH}" "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/mergerfs-fusermount$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/fsck.mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/mergerfs.collect-info$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -Eq '/(usr/)?sbin/mount.mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/lib/mergerfs/preload.so$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/mergerfs/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/mergerfs/README.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: ISC$' "${OUT_DIR}/metadata/rpm-info.txt"

printf 'Built mergerfs %s x86-64-v2 RPM from %s\n' \
    "${MERGERFS_VERSION}" "${MERGERFS_COMMIT}"
