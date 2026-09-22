#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/nm-hsp"
SRC_DIR="${ROOT_DIR}/.work/nm-hsp"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-nm-hsp"

source "${PKG_DIR}/package.env"

RPM_ARCH="${RPM_ARCH:-$(uname -m)}"
case "${RPM_ARCH}" in
  x86_64) GOARCH=amd64 ;;
  aarch64) GOARCH=arm64 ;;
  *)
    echo "ERROR: unsupported RPM architecture: ${RPM_ARCH}" >&2
    exit 1
    ;;
esac

OUT_DIR="${ROOT_DIR}/out/nm-hsp/${RPM_ARCH}"
PAYLOAD_DIR="${ROOT_DIR}/.work/nm-hsp-payload-${RPM_ARCH}"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}"
mkdir -p   "${SRC_DIR}"   "${OUT_DIR}/rpms"   "${OUT_DIR}/source"   "${OUT_DIR}/licenses"   "${OUT_DIR}/metadata"   "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

git clone --filter=blob:none --no-checkout "${NM_HSP_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"
git fetch --force origin "${NM_HSP_COMMIT}"
git checkout --detach "${NM_HSP_COMMIT}"

test "$(git rev-parse HEAD)" = "${NM_HSP_COMMIT}"
test -f LICENSE
test -f README.md
test -f go.mod
test -f go.sum

export GOTOOLCHAIN=auto
go env GOVERSION > "${OUT_DIR}/metadata/go-version.txt"
go mod verify
go test ./...

CGO_ENABLED=0 GOOS=linux GOARCH="${GOARCH}"   go build -trimpath -o "${OUT_DIR}/nm-hsp" ./cmd/nm-hsp

test -x "${OUT_DIR}/nm-hsp"
file "${OUT_DIR}/nm-hsp" | tee "${OUT_DIR}/metadata/binary-file.txt"

case "${RPM_ARCH}" in
  x86_64)
    readelf -h "${OUT_DIR}/nm-hsp" | grep -Fq 'Advanced Micro Devices X86-64'
    ;;
  aarch64)
    readelf -h "${OUT_DIR}/nm-hsp" | grep -Fq 'AArch64'
    ;;
esac

if readelf -l "${OUT_DIR}/nm-hsp" | grep -q 'Requesting program interpreter'; then
  echo "ERROR: nm-hsp binary unexpectedly requires a dynamic ELF interpreter" >&2
  exit 1
fi

mkdir -p   "${PAYLOAD_DIR}/usr/bin"   "${PAYLOAD_DIR}/usr/share/licenses/nm-hsp"   "${PAYLOAD_DIR}/usr/share/doc/nm-hsp"

install -Dm0755 "${OUT_DIR}/nm-hsp" "${PAYLOAD_DIR}/usr/bin/nm-hsp"
install -Dm0644 LICENSE "${PAYLOAD_DIR}/usr/share/licenses/nm-hsp/LICENSE"
install -Dm0644 README.md "${PAYLOAD_DIR}/usr/share/doc/nm-hsp/README.md"

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/nm-hsp-payload.tar.gz" .
cp "${PKG_DIR}/nm-hsp.spec" "${RPMBUILD_DIR}/SPECS/nm-hsp.spec"

rpmbuild -bb   --target "${RPM_ARCH}"   --define "_topdir ${RPMBUILD_DIR}"   --define "nm_hsp_version ${NM_HSP_VERSION}"   --define "rpm_arch ${RPM_ARCH}"   "${RPMBUILD_DIR}/SPECS/nm-hsp.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name "nm-hsp-*.${RPM_ARCH}.rpm"   -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name "nm-hsp-*.${RPM_ARCH}.rpm" -print -quit)"

git archive --format=tar.gz --prefix="nm-hsp-${NM_HSP_VERSION}/"   -o "${OUT_DIR}/source/nm-hsp-${NM_HSP_VERSION}-${NM_HSP_COMMIT}.tar.gz"   "${NM_HSP_COMMIT}"
cp "${PKG_DIR}/nm-hsp.spec" "${OUT_DIR}/source/nm-hsp.spec"
install -Dm0644 LICENSE "${OUT_DIR}/licenses/LICENSE"

cat > "${OUT_DIR}/metadata/package.env" <<EOF
PACKAGE=nm-hsp
VERSION=${NM_HSP_VERSION}
UPSTREAM_COMMIT=${NM_HSP_COMMIT}
LICENSE=${NM_HSP_LICENSE}
UPSTREAM=${NM_HSP_UPSTREAM}
PACKAGE_CHANNEL=universal
RPM_ARCH=${RPM_ARCH}
GOARCH=${GOARCH}
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

grep -Fqx "${RPM_ARCH}" "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/nm-hsp$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/nm-hsp/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/nm-hsp/README.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: Apache-2.0$' "${OUT_DIR}/metadata/rpm-info.txt"

printf 'Built nm-hsp %s RPM for %s from %s\n'   "${NM_HSP_VERSION}" "${RPM_ARCH}" "${NM_HSP_COMMIT}"
