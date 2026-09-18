#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/mergerfs"
OUT_DIR="${ROOT_DIR}/out/mergerfs"
SRC_DIR="${ROOT_DIR}/.work/mergerfs"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-mergerfs"

: "${EXPECTED_RPM_ARCH:?EXPECTED_RPM_ARCH must be set}"
: "${PACKAGE_CHANNEL:?PACKAGE_CHANNEL must be set}"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}"
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

rpm_arch="$(rpm --eval '%{_arch}')"
if [[ "${rpm_arch}" != "${EXPECTED_RPM_ARCH}" ]]; then
    echo "ERROR: build environment RPM architecture is ${rpm_arch}; expected ${EXPECTED_RPM_ARCH}" >&2
    exit 1
fi

# Compile and run upstream's C++ unit-test binary before packaging.
make RELEASE=1 tests
./build/tests

git archive \
    --format=tar.gz \
    --prefix="mergerfs-${MERGERFS_VERSION}/" \
    -o "${RPMBUILD_DIR}/SOURCES/mergerfs-${MERGERFS_VERSION}.tar.gz" \
    "${MERGERFS_COMMIT}"

cp "${PKG_DIR}/mergerfs.spec" "${RPMBUILD_DIR}/SPECS/mergerfs.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "mergerfs_version ${MERGERFS_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/mergerfs.spec"

RPM_FILE="$(find "${RPMBUILD_DIR}/RPMS" -type f -name 'mergerfs-*.rpm' -print -quit)"
test -n "${RPM_FILE}"

built_arch="$(rpm -qp --qf '%{ARCH}\n' "${RPM_FILE}")"
if [[ "${built_arch}" != "${EXPECTED_RPM_ARCH}" ]]; then
    echo "ERROR: built mergerfs RPM architecture is ${built_arch}; expected ${EXPECTED_RPM_ARCH}" >&2
    exit 1
fi

cp -v "${RPM_FILE}" "${OUT_DIR}/rpms/"

# Keep exact source, packaging recipe, license, and provenance with the artifact.
git archive \
    --format=tar.gz \
    --prefix="mergerfs-${MERGERFS_VERSION}/" \
    -o "${OUT_DIR}/source/mergerfs-${MERGERFS_VERSION}-${MERGERFS_COMMIT}.tar.gz" \
    "${MERGERFS_COMMIT}"
cp "${PKG_DIR}/mergerfs.spec" "${OUT_DIR}/source/mergerfs.spec"
install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"
install -Dm0644 README.md "${OUT_DIR}/source/README.md"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=mergerfs
VERSION=${MERGERFS_VERSION}
UPSTREAM_COMMIT=${MERGERFS_COMMIT}
LICENSE=${MERGERFS_LICENSE}
UPSTREAM=${MERGERFS_UPSTREAM}
PACKAGE_CHANNEL=${PACKAGE_CHANNEL}
RPM_ARCH=${EXPECTED_RPM_ARCH}
EOF

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
printf '%s\n' "${built_arch}" > "${OUT_DIR}/metadata/rpm-arch.txt"

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/* > metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

# Package and license/compliance gates.
grep -q "^${EXPECTED_RPM_ARCH}$" "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/mergerfs-fusermount$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/fsck.mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/mergerfs.collect-info$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -Eq '/(usr/)?sbin/mount.mergerfs$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/lib/mergerfs/preload.so$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/mergerfs/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: ISC$' "${OUT_DIR}/metadata/rpm-info.txt"

# Install and exercise the exact RPM produced above.
dnf install -y "${RPM_FILE}"
rpm -q mergerfs
rpm -V mergerfs
/usr/bin/mergerfs --version | tee "${OUT_DIR}/metadata/mergerfs-version.txt"
grep -Fq "${MERGERFS_VERSION}" "${OUT_DIR}/metadata/mergerfs-version.txt"

readelf -h /usr/bin/mergerfs > "${OUT_DIR}/metadata/mergerfs-elf.txt"
file /usr/bin/mergerfs >> "${OUT_DIR}/metadata/mergerfs-elf.txt"

# Functional FUSE gate: mount two branches, read both, write through the pool,
# then unmount. Publication is blocked if this basic filesystem path fails.
TEST_ROOT="$(mktemp -d)"
mkdir -p "${TEST_ROOT}/a" "${TEST_ROOT}/b" "${TEST_ROOT}/pool"
printf 'branch-a\n' > "${TEST_ROOT}/a/a.txt"
printf 'branch-b\n' > "${TEST_ROOT}/b/b.txt"

cleanup() {
    if mountpoint -q "${TEST_ROOT}/pool"; then
        umount "${TEST_ROOT}/pool" || true
    fi
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

/usr/bin/mergerfs -f "${TEST_ROOT}/a:${TEST_ROOT}/b" "${TEST_ROOT}/pool" &
MFS_PID=$!

mounted=0
for _ in $(seq 1 20); do
    if mountpoint -q "${TEST_ROOT}/pool"; then
        mounted=1
        break
    fi
    sleep 0.25
done

if [[ "${mounted}" -ne 1 ]]; then
    echo "ERROR: mergerfs functional test did not mount" >&2
    kill "${MFS_PID}" >/dev/null 2>&1 || true
    wait "${MFS_PID}" >/dev/null 2>&1 || true
    exit 1
fi

grep -Fqx 'branch-a' "${TEST_ROOT}/pool/a.txt"
grep -Fqx 'branch-b' "${TEST_ROOT}/pool/b.txt"
printf 'through-pool\n' > "${TEST_ROOT}/pool/write-test.txt"
grep -Fqx 'through-pool' "${TEST_ROOT}/pool/write-test.txt"

umount "${TEST_ROOT}/pool"
wait "${MFS_PID}" >/dev/null 2>&1 || true
trap - EXIT
rm -rf "${TEST_ROOT}"

printf 'Built and validated mergerfs %s from %s for %s (%s)\n' \
    "${MERGERFS_VERSION}" "${MERGERFS_COMMIT}" "${PACKAGE_CHANNEL}" "${EXPECTED_RPM_ARCH}"
