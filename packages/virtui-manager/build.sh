#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages/virtui-manager"
PYTHON_DIR="${PKG_DIR}/python"
OUT_DIR="${ROOT_DIR}/out/virtui-manager"
SRC_DIR="${ROOT_DIR}/.work/virtui-manager"
RPMBUILD_DIR="${ROOT_DIR}/.work/rpmbuild-virtui-manager"
PAYLOAD_DIR="${ROOT_DIR}/.work/virtui-manager-payload"
PRIVATE_DIR="${PAYLOAD_DIR}/usr/libexec/virtui-manager/python"
LOCKED_REQUIREMENTS="${OUT_DIR}/metadata/private-requirements.txt"

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
    "${PAYLOAD_DIR}/usr/share/licenses/virtui-manager/python" \
    "${PAYLOAD_DIR}/usr/share/doc/virtui-manager"

git clone --filter=blob:none --no-checkout "${VIRTUI_MANAGER_UPSTREAM}.git" "${SRC_DIR}"
cd "${SRC_DIR}"

git fetch --force --tags origin \
    "refs/tags/v${VIRTUI_MANAGER_VERSION}:refs/tags/v${VIRTUI_MANAGER_VERSION}"
TAG_COMMIT="$(git rev-parse "refs/tags/v${VIRTUI_MANAGER_VERSION}^{commit}")"

if [[ "${TAG_COMMIT}" != "${VIRTUI_MANAGER_COMMIT}" ]]; then
    echo "ERROR: VirtUI Manager tag v${VIRTUI_MANAGER_VERSION} resolves to ${TAG_COMMIT}, expected ${VIRTUI_MANAGER_COMMIT}" >&2
    exit 1
fi

git checkout --detach "${VIRTUI_MANAGER_COMMIT}"

test -f LICENSE
test -f README.md
test -f pyproject.toml
test -d tests
test -f checks/check_versions.py
test -f checks/check_constants.py
test -f checks/find_missing_msgstr.py

# Verify upstream metadata and ensure our pinned private Textual version satisfies
# the requirement declared by this exact VirtUI release.
readarray -t VIRTUI_METADATA < <(
    PYTHON_PROJECT="${PYTHON_DIR}/pyproject.toml" \
    VIRTUI_VERSION="${VIRTUI_MANAGER_VERSION}" \
    python3 - <<'PY'
import os
import tomllib
from packaging.requirements import Requirement
from packaging.version import Version

with open("pyproject.toml", "rb") as fh:
    upstream = tomllib.load(fh)
with open(os.environ["PYTHON_PROJECT"], "rb") as fh:
    private = tomllib.load(fh)

expected_version = os.environ["VIRTUI_VERSION"]
actual_version = upstream["project"]["version"]
if actual_version != expected_version:
    raise SystemExit(
        f"VirtUI source version {actual_version} does not match package version {expected_version}"
    )

license_value = upstream["project"].get("license")
if license_value != "GPL-3.0-or-later":
    raise SystemExit(f"Unexpected VirtUI license declaration: {license_value!r}")

upstream_textual = None
for dependency in upstream["project"]["dependencies"]:
    req = Requirement(dependency)
    if req.name.lower() == "textual":
        upstream_textual = req
        break
if upstream_textual is None:
    raise SystemExit("VirtUI no longer declares a Textual dependency")

private_dependencies = private["project"]["dependencies"]
if len(private_dependencies) != 1:
    raise SystemExit("Private Python project must declare only the Textual root dependency")
private_textual = Requirement(private_dependencies[0])
if private_textual.name.lower() != "textual" or len(private_textual.specifier) != 1:
    raise SystemExit("Private Textual dependency must be an exact pin")

spec = next(iter(private_textual.specifier))
if spec.operator not in ("==", "===") or "*" in spec.version:
    raise SystemExit("Private Textual dependency must be an exact version pin")
textual_version = spec.version

if Version(textual_version) not in upstream_textual.specifier:
    raise SystemExit(
        f"Pinned Textual {textual_version} does not satisfy upstream requirement "
        f"{upstream_textual.specifier}"
    )

print(textual_version)
print(str(upstream_textual.specifier))
PY
)
TEXTUAL_VERSION="${VIRTUI_METADATA[0]}"
UPSTREAM_TEXTUAL_SPEC="${VIRTUI_METADATA[1]}"

# The committed uv lock is authoritative. Every private dependency must have an
# expected license entry and must resolve only to architecture-independent wheels.
PYTHON_LOCK="${PYTHON_DIR}/uv.lock" \
LICENSE_MANIFEST="${PYTHON_DIR}/python-licenses.tsv" \
TEXTUAL_VERSION="${TEXTUAL_VERSION}" \
python3 - <<'PY'
import os
import re
import tomllib
from pathlib import Path

lock_path = Path(os.environ["PYTHON_LOCK"])
manifest_path = Path(os.environ["LICENSE_MANIFEST"])
textual_version = os.environ["TEXTUAL_VERSION"]


def normalize_name(name):
    return re.sub(r"[-_.]+", "-", name).lower()


with lock_path.open("rb") as fh:
    lock = tomllib.load(fh)

expected = {}
for raw in manifest_path.read_text().splitlines():
    raw = raw.strip()
    if not raw or raw.startswith("#"):
        continue
    name, spdx = raw.split("\t", 1)
    expected[normalize_name(name)] = spdx

registry_packages = {}
for package in lock.get("package", []):
    source = package.get("source", {})
    if "registry" not in source:
        continue
    name = normalize_name(package["name"])
    registry_packages[name] = package["version"]
    wheels = package.get("wheels", [])
    if not wheels:
        raise SystemExit(f"Locked package {name} has no wheel")
    for wheel in wheels:
        url = wheel.get("url", "")
        if not url.endswith("-py3-none-any.whl"):
            raise SystemExit(f"Locked package {name} is not architecture-independent: {url}")
        digest = wheel.get("hash", "")
        if not digest.startswith("sha256:") or len(digest) != 71:
            raise SystemExit(f"Locked package {name} has no usable SHA-256 wheel hash")

if registry_packages != {k: registry_packages.get(k) for k in expected}:
    missing = sorted(set(expected) - set(registry_packages))
    extra = sorted(set(registry_packages) - set(expected))
    raise SystemExit(f"Python license manifest mismatch; missing={missing}, extra={extra}")

if registry_packages.get("textual") != textual_version:
    raise SystemExit(
        f"uv.lock contains Textual {registry_packages.get('textual')}, expected {textual_version}"
    )
PY

(
    cd "${PYTHON_DIR}"
    uv lock --check
    uv export --frozen --no-dev --format requirements-txt \
        --output-file "${LOCKED_REQUIREMENTS}"
)

# Install only the hash-locked portable Python closure into the private tree.
uv pip install \
    --python python3 \
    --target "${PRIVATE_DIR}" \
    --no-compile \
    --require-hashes \
    --requirements "${LOCKED_REQUIREMENTS}"

# Install VirtUI itself from the exact verified source without allowing pip to
# resolve or replace any dependencies.
python3 -m pip install \
    --no-deps \
    --no-build-isolation \
    --no-compile \
    --target "${PRIVATE_DIR}" \
    .
rm -rf "${PRIVATE_DIR}/bin"

# Run the meaningful upstream CI checks against the exact package payload.
export PYTHONPATH="${PRIVATE_DIR}:${SRC_DIR}/src"
python3 checks/check_versions.py
python3 checks/check_constants.py
python3 checks/find_missing_msgstr.py
python3 -m pytest tests/test_* --tb=line

python3 - <<PY
from importlib.metadata import version
assert version("virtui-manager") == "${VIRTUI_MANAGER_VERSION}"
assert version("textual") == "${TEXTUAL_VERSION}"
import textual
import vmanager.wrapper
print("VirtUI Manager", version("virtui-manager"))
print("Textual", version("textual"))
PY

# Tests import the private tree, so remove generated bytecode before packaging.
find "${PRIVATE_DIR}" -type d -name __pycache__ -prune -exec rm -rf {} +
find "${PRIVATE_DIR}" -type f -name '*.pyc' -delete

if find "${PRIVATE_DIR}" -type f -print0 | xargs -0 file | grep -q 'ELF'; then
    echo "ERROR: private VirtUI Python tree contains an ELF file; RPM can no longer be noarch" >&2
    exit 1
fi

install -Dm0644 LICENSE \
    "${PAYLOAD_DIR}/usr/share/licenses/virtui-manager/LICENSE"
install -Dm0644 README.md \
    "${PAYLOAD_DIR}/usr/share/doc/virtui-manager/README.md"
install -Dm0644 "${PYTHON_DIR}/python-licenses.tsv" \
    "${PAYLOAD_DIR}/usr/share/licenses/virtui-manager/python/manifest.tsv"

# Copy license material from every wheel in the private dependency lock. Missing
# license files are a hard failure rather than a silent redistribution gap.
PRIVATE_DIR="${PRIVATE_DIR}" \
LICENSE_MANIFEST="${PYTHON_DIR}/python-licenses.tsv" \
LICENSE_DEST="${PAYLOAD_DIR}/usr/share/licenses/virtui-manager/python" \
python3 - <<'PY'
import importlib.metadata
import os
import re
import shutil
from pathlib import Path

private = Path(os.environ["PRIVATE_DIR"])
dest_root = Path(os.environ["LICENSE_DEST"])
manifest = Path(os.environ["LICENSE_MANIFEST"])


def normalize_name(name):
    return re.sub(r"[-_.]+", "-", name).lower()


expected = {}
for raw in manifest.read_text().splitlines():
    raw = raw.strip()
    if not raw or raw.startswith("#"):
        continue
    name, spdx = raw.split("\t", 1)
    expected[normalize_name(name)] = spdx

dists = {
    normalize_name(dist.metadata["Name"]): dist
    for dist in importlib.metadata.distributions(path=[str(private)])
    if dist.metadata.get("Name")
}

for name, spdx in sorted(expected.items()):
    dist = dists.get(name)
    if dist is None:
        raise SystemExit(f"Locked Python package {name} is missing from private payload")

    metadata_text = "\n".join(
        [
            dist.metadata.get("License-Expression", ""),
            dist.metadata.get("License", ""),
            *dist.metadata.get_all("Classifier", []),
        ]
    ).lower()
    expected_markers = {
        "MIT": ("mit",),
        "BSD-2-Clause": ("bsd-2-clause", "bsd license"),
        "PSF-2.0": ("psf-2.0", "python software foundation"),
    }[spdx]
    if not any(marker in metadata_text for marker in expected_markers):
        raise SystemExit(
            f"Locked Python package {name} no longer advertises expected license {spdx}"
        )

    dist_info = Path(dist._path)
    candidates = []
    for path in dist_info.rglob("*"):
        if not path.is_file():
            continue
        upper = path.name.upper()
        if upper.startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE")):
            candidates.append(path)

    if not candidates:
        raise SystemExit(f"Locked Python package {name} has no license file in its wheel")

    package_dest = dest_root / name
    package_dest.mkdir(parents=True, exist_ok=True)
    (package_dest / "SPDX").write_text(spdx + "\n")
    for source in candidates:
        relative = source.relative_to(dist_info)
        target_name = "__".join(relative.parts)
        shutil.copy2(source, package_dest / target_name)
PY

# Build the noarch RPM from the completed private payload.
tar -C "${PAYLOAD_DIR}" -czf \
    "${RPMBUILD_DIR}/SOURCES/virtui-manager-payload.tar.gz" .
cp "${PKG_DIR}/virtui-manager.spec" \
    "${RPMBUILD_DIR}/SPECS/virtui-manager.spec"

rpmbuild -bb \
    --define "_topdir ${RPMBUILD_DIR}" \
    --define "virtui_version ${VIRTUI_MANAGER_VERSION}" \
    "${RPMBUILD_DIR}/SPECS/virtui-manager.spec"

find "${RPMBUILD_DIR}/RPMS" -type f -name 'virtui-manager-*.noarch.rpm' \
    -exec cp -v {} "${OUT_DIR}/rpms/" \;
test -n "$(find "${OUT_DIR}/rpms" -maxdepth 1 -type f -name 'virtui-manager-*.noarch.rpm' -print -quit)"

# Retain exact GPL source plus the full private dependency declaration/lock and
# packaging recipe with each published artifact.
git archive --format=tar.gz --prefix="virtui-manager-${VIRTUI_MANAGER_VERSION}/" \
    -o "${OUT_DIR}/source/virtui-manager-${VIRTUI_MANAGER_VERSION}-${VIRTUI_MANAGER_COMMIT}.tar.gz" \
    "${VIRTUI_MANAGER_COMMIT}"
cp "${PKG_DIR}/virtui-manager.spec" "${OUT_DIR}/source/virtui-manager.spec"
cp "${PKG_DIR}/package.env" "${OUT_DIR}/source/package.env"
cp "${PYTHON_DIR}/pyproject.toml" "${OUT_DIR}/source/private-python-pyproject.toml"
cp "${PYTHON_DIR}/uv.lock" "${OUT_DIR}/source/private-python-uv.lock"
cp "${PYTHON_DIR}/python-licenses.tsv" "${OUT_DIR}/source/private-python-licenses.tsv"
cp "${LOCKED_REQUIREMENTS}" "${OUT_DIR}/source/private-python-requirements.txt"
cp -a "${PAYLOAD_DIR}/usr/share/licenses/virtui-manager/." "${OUT_DIR}/licenses/"

PYTHON_LOCK="${PYTHON_DIR}/uv.lock" \
LICENSE_MANIFEST="${PYTHON_DIR}/python-licenses.tsv" \
python3 - <<'PY' > "${OUT_DIR}/metadata/private-python-packages.tsv"
import os
import tomllib
from pathlib import Path

with Path(os.environ["PYTHON_LOCK"]).open("rb") as fh:
    lock = tomllib.load(fh)
licenses = {}
for raw in Path(os.environ["LICENSE_MANIFEST"]).read_text().splitlines():
    raw = raw.strip()
    if not raw or raw.startswith("#"):
        continue
    name, spdx = raw.split("\t", 1)
    licenses[name.lower()] = spdx

print("package\tversion\tSPDX")
for package in sorted(lock["package"], key=lambda p: p["name"]):
    if "registry" not in package.get("source", {}):
        continue
    name = package["name"]
    print(f"{name}\t{package['version']}\t{licenses[name.lower()]}")
PY

LOCK_SHA256="$(sha256sum "${PYTHON_DIR}/uv.lock" | awk '{print $1}')"
cat > "${OUT_DIR}/metadata/package.env" <<EOF_META
PACKAGE=virtui-manager
VERSION=${VIRTUI_MANAGER_VERSION}
UPSTREAM_COMMIT=${VIRTUI_MANAGER_COMMIT}
LICENSE=${VIRTUI_MANAGER_LICENSE}
UPSTREAM=${VIRTUI_MANAGER_UPSTREAM}
PACKAGE_CHANNEL=universal-noarch
TEXTUAL_VERSION=${TEXTUAL_VERSION}
UPSTREAM_TEXTUAL_SPEC=${UPSTREAM_TEXTUAL_SPEC}
PRIVATE_PYTHON_LOCK_SHA256=${LOCK_SHA256}
EOF_META

(
    cd "${OUT_DIR}"
    sha256sum rpms/* source/* > metadata/SHA256SUMS
    find licenses -type f -print0 | sort -z | xargs -0 sha256sum >> metadata/SHA256SUMS
    sha256sum rpms/*.rpm > metadata/rpm-sha256.txt
)

rpm -qpl "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-files.txt"
rpm -qpR "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-requires.txt"
rpm -qpi "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-info.txt"
rpm -qp --qf '%{ARCH}\n' "${OUT_DIR}"/rpms/*.rpm > "${OUT_DIR}/metadata/rpm-arch.txt"

# Package/compliance gates.
grep -q '^noarch$' "${OUT_DIR}/metadata/rpm-arch.txt"
grep -q '/usr/bin/virtui-manager$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/virtui-manager-cmd$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/bin/vmc$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/libexec/virtui-manager/python/' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/virtui-manager/LICENSE$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/licenses/virtui-manager/python/manifest.tsv$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '/usr/share/doc/virtui-manager/README.md$' "${OUT_DIR}/metadata/rpm-files.txt"
grep -q '^License *: GPL-3.0-or-later$' "${OUT_DIR}/metadata/rpm-info.txt"

printf 'Built VirtUI Manager %s noarch RPM from %s with Textual %s\n' \
    "${VIRTUI_MANAGER_VERSION}" "${VIRTUI_MANAGER_COMMIT}" "${TEXTUAL_VERSION}"
