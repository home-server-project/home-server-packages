#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/playit"
OUT_DIR="${ROOT_DIR}/out/playit"
SRC_DIR="${ROOT_DIR}/.work/playit"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-playit"
PAYLOAD_DIR="${ROOT_DIR}/.work/playit-payload"
CARGO_HOME_DIR="${ROOT_DIR}/.work/cargo-playit"

source "${PKG_DIR}/package.env"

rm -rf "${SRC_DIR}" "${OUT_DIR}" "${RPMBUILD_DIR}" "${PAYLOAD_DIR}" "${CARGO_HOME_DIR}"
mkdir -p \
    "${SRC_DIR}" \
    "${OUT_DIR}/rpms" \
    "${OUT_DIR}/source" \
    "${OUT_DIR}/licenses/rust-dependencies" \
    "${OUT_DIR}/metadata" \
    "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    "${PAYLOAD_DIR}/opt/playit/share/init/systemd" \
    "${PAYLOAD_DIR}/opt/playit/share/init/openrc" \
    "${PAYLOAD_DIR}/usr/bin" \
    "${PAYLOAD_DIR}/usr/lib/systemd/system" \
    "${PAYLOAD_DIR}/usr/lib/sysusers.d" \
    "${PAYLOAD_DIR}/usr/lib/tmpfiles.d" \
    "${PAYLOAD_DIR}/etc/logrotate.d" \
    "${PAYLOAD_DIR}/usr/share/licenses/playit/rust-dependencies" \
    "${PAYLOAD_DIR}/usr/share/doc/playit" \
    "${CARGO_HOME_DIR}"

git clone --filter=blob:none --no-checkout "${PLAYIT_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin "refs/tags/v${PLAYIT_VERSION}:refs/tags/v${PLAYIT_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/v${PLAYIT_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${PLAYIT_COMMIT}" ]]; then
    echo "ERROR: Playit tag v${PLAYIT_VERSION} resolves to ${TAG_COMMIT}, expected ${PLAYIT_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${PLAYIT_COMMIT}"

test -f Cargo.toml
test -f Cargo.lock
test -f LICENSE.txt
test -f README.md
test -f linux/playit
test -f linux/playit.service
test -f linux/playit.openrc
test -f linux/playit.sysusers
test -f linux/logrotate.conf

PLAYIT_EXPECTED_VERSION="${PLAYIT_VERSION}" python3 - <<'PY'
import os
import tomllib
from pathlib import Path

with Path("Cargo.toml").open("rb") as fh:
    data = tomllib.load(fh)

actual = data["workspace"]["package"]["version"]
expected = os.environ["PLAYIT_EXPECTED_VERSION"]
if actual != expected:
    raise SystemExit(f"Playit source version {actual!r} does not match expected {expected!r}")
PY

grep -Fq 'Copyright 2022 Developed Methods LLC' LICENSE.txt

export CARGO_HOME="${CARGO_HOME_DIR}"

cargo --version | tee "${OUT_DIR}/metadata/cargo-version.txt"
rustc --version | tee "${OUT_DIR}/metadata/rustc-version.txt"
cargo fetch --locked
cargo metadata --locked --format-version 1 > "${OUT_DIR}/metadata/cargo-metadata.json"

cargo test --locked \
    --package playit-cli \
    --package playit-ipc \
    --package playitd \
    --package playit-agent-core \
    --package playit-agent-proto \
    --package playit-api-client

cargo build --locked --release \
    --package playit-cli \
    --package playitd

test -x target/release/playit-cli
test -x target/release/playitd

target/release/playit-cli version | tee "${OUT_DIR}/metadata/playit-version.txt"
grep -Fqx "${PLAYIT_VERSION}" "${OUT_DIR}/metadata/playit-version.txt"

# Preserve license metadata and available license/notice files for the Rust
# dependency set resolved by the committed Cargo.lock.
PLAYIT_CARGO_HOME="${CARGO_HOME}" \
PLAYIT_LICENSE_OUT="${OUT_DIR}/licenses/rust-dependencies" \
PLAYIT_LICENSE_TSV="${OUT_DIR}/licenses/RUST-DEPENDENCIES.tsv" \
python3 - <<'PY'
import json
import os
import shutil
from pathlib import Path

cargo_home = Path(os.environ["PLAYIT_CARGO_HOME"])
license_out = Path(os.environ["PLAYIT_LICENSE_OUT"])
tsv_path = Path(os.environ["PLAYIT_LICENSE_TSV"])
metadata = json.loads(Path(os.environ.get("PLAYIT_METADATA", "out-not-used")).read_text()) if False else None
metadata_path = Path.cwd().parents[1] / "out" / "playit" / "metadata" / "cargo-metadata.json"
data = json.loads(metadata_path.read_text())

registry_roots = list((cargo_home / "registry" / "src").glob("*"))
rows = ["name\tversion\tlicense\tlicense_file\tretained_files"]

for pkg in sorted(data["packages"], key=lambda p: (p["name"], p["version"])):
    source = pkg.get("source") or ""
    if not source.startswith("registry+"):
        continue

    name = pkg["name"]
    version = pkg["version"]
    license_expr = pkg.get("license") or ""
    license_file = pkg.get("license_file") or ""

    matches = []
    for root in registry_roots:
        candidate = root / f"{name}-{version}"
        if candidate.is_dir():
            matches.append(candidate)

    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one Cargo source directory for {name} {version}, found {len(matches)}")

    src = matches[0]
    candidates = []
    if license_file:
        p = src / license_file
        if p.is_file():
            candidates.append(p)

    for p in src.iterdir():
        if not p.is_file():
            continue
        upper = p.name.upper()
        if upper.startswith(("LICENSE", "COPYING", "COPYRIGHT", "NOTICE")):
            candidates.append(p)

    unique = []
    seen = set()
    for p in candidates:
        key = p.resolve()
        if key not in seen:
            seen.add(key)
            unique.append(p)

    if not license_expr and not license_file:
        raise SystemExit(f"Cargo dependency {name} {version} has no declared license metadata")
    if not unique:
        raise SystemExit(f"Cargo dependency {name} {version} has no retained license/notice file")

    dest = license_out / f"{name}-{version}"
    dest.mkdir(parents=True, exist_ok=True)
    retained = []
    for p in unique:
        target = dest / p.name
        shutil.copy2(p, target)
        retained.append(p.name)

    rows.append(
        "\t".join([
            name,
            version,
            license_expr,
            license_file,
            ",".join(sorted(retained)),
        ])
    )

tsv_path.write_text("\n".join(rows) + "\n")
PY

install -Dm0755 target/release/playit-cli "${PAYLOAD_DIR}/opt/playit/agent"
install -Dm0755 target/release/playitd "${PAYLOAD_DIR}/opt/playit/playitd"
install -Dm0755 linux/playit "${PAYLOAD_DIR}/opt/playit/playit"
install -Dm0644 linux/playit.service "${PAYLOAD_DIR}/usr/lib/systemd/system/playit.service"
install -Dm0644 linux/playit.service "${PAYLOAD_DIR}/opt/playit/share/init/systemd/playit.service"
install -Dm0755 linux/playit.openrc "${PAYLOAD_DIR}/opt/playit/share/init/openrc/playit"
install -Dm0644 linux/playit.sysusers "${PAYLOAD_DIR}/usr/lib/sysusers.d/playit.conf"
install -Dm0644 linux/logrotate.conf "${PAYLOAD_DIR}/etc/logrotate.d/playit"
printf '%s\n' systemd > "${PAYLOAD_DIR}/opt/playit/share/init/selected-manager"
printf '%s\n' 'd /etc/playit 0750 playit playit -' > "${PAYLOAD_DIR}/usr/lib/tmpfiles.d/playit.conf"
ln -s /opt/playit/playit "${PAYLOAD_DIR}/usr/bin/playit"
ln -s /opt/playit/playitd "${PAYLOAD_DIR}/usr/bin/playitd"
install -Dm0644 LICENSE.txt "${PAYLOAD_DIR}/usr/share/licenses/playit/LICENSE.txt"
install -Dm0644 "${OUT_DIR}/licenses/RUST-DEPENDENCIES.tsv" \
    "${PAYLOAD_DIR}/usr/share/licenses/playit/RUST-DEPENDENCIES.tsv"
cp -a "${OUT_DIR}/licenses/rust-dependencies/." \
    "${PAYLOAD_DIR}/usr/share/licenses/playit/rust-dependencies/"
install -Dm0644 README.md "${PAYLOAD_DIR}/usr/share/doc/playit/README.md"

tar -C "${PAYLOAD_DIR}" -czf "${RPMBUILD_DIR}/SOURCES/playit-payload.tar.gz" .
cp "${PKG_DIR}/playit.spec" "${RPMBUILD_DIR}/SPECS/playit.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "playit_version ${PLAYIT_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/playit.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'playit-*.x86_64.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'playit-*.x86_64.rpm' -print -quit)"

git archive --format=tar.gz --prefix="playit-${PLAYIT_VERSION}/" \
    -o "${OUT_DIR}/source/playit-${PLAYIT_VERSION}-${PLAYIT_COMMIT}.tar.gz" \
    "${PLAYIT_COMMIT}"
cp "${PKG_DIR}/playit.spec" "${OUT_DIR}/source/playit.spec"
cp "${PKG_DIR}/package.env" "${OUT_DIR}/source/package.env"
install -Dm0644 LICENSE.txt "${OUT_DIR}/licenses/LICENSE.txt"

cat > "${OUT_DIR}/metadata/package.env" <<EOF_META
PACKAGE=playit
VERSION=${PLAYIT_VERSION}
UPSTREAM_COMMIT=${PLAYIT_COMMIT}
LICENSE=${PLAYIT_LICENSE}
UPSTREAM=${PLAYIT_UPSTREAM}
PACKAGE_CHANNEL=el10-x86_64
EOF_META

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* licenses/LICENSE.txt licenses/RUST-DEPENDENCIES.tsv > metadata/SHA256SUMS
    find licenses/rust-dependencies -type f -print0 | sort -z | xargs -0 sha256sum >> metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
rpm -qp --qf '%{ARCH}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-arch.txt"
rpm -qp --qf '%{SIZE}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-installed-size.txt"

grep -Fqx 'x86_64' "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/playit$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/playitd$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/lib/systemd/system/playit.service$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/lib/sysusers.d/playit.conf$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/lib/tmpfiles.d/playit.conf$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/playit/LICENSE.txt$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/playit/RUST-DEPENDENCIES.tsv$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: BSD-2-Clause$' "${OUT_DIR}/metadata/rpm-info.txt"
grep -Fq 'logrotate' "${OUT_DIR}/metadata/rpm-requires.txt"

printf 'Built Playit %s AlmaLinux 10 x86_64 RPM from %s\n' \
    "${PLAYIT_VERSION}" "${PLAYIT_COMMIT}"
