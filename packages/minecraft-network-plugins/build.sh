#!/usr/bin/env bash
set -euo pipefail
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${package_dir}/../.." && pwd)"
source "${package_dir}/package.env"
command -v java >/dev/null
java_properties="$(java -XshowSettings:properties -version 2>&1)"
grep -Eq '^[[:space:]]*java.specification.version = 25$' <<<"${java_properties}"
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
output="${root}/out/minecraft-network-plugins"
rm -rf -- "${output}"
mkdir -p "${output}"/{artifacts,metadata,source,licenses}
python3 "${package_dir}/acquire.py" "${work}/inputs"
install -m0644 "${work}/inputs/limboapi.jar" "${output}/artifacts/limboapi.jar"
cp "${work}/inputs/"*-release.json "${output}/metadata/"

# The official checksum must agree with the reviewed distribution checksum.
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip.sha256" -o "${work}/gradle.sha256"
[[ "$(cat "${work}/gradle.sha256")" == "${GRADLE_SHA256}" ]]
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o "${work}/gradle.zip"
printf '%s  %s\n' "${GRADLE_SHA256}" "${work}/gradle.zip" | sha256sum --check --status
unzip -q "${work}/gradle.zip" -d "${work}"
"${work}/gradle-${GRADLE_VERSION}/bin/gradle" --no-daemon -p "${package_dir}/velocity-lobby" \
    --gradle-user-home "${work}/gradle-home" --project-cache-dir "${work}/gradle-project-cache" \
    "-PbuildOutputDir=${work}/gradle-build" "-PlimboApiJar=${work}/inputs/limboapi.jar" \
    "-PvelocityVersion=${VELOCITY_VERSION}" "-PvelocityServerJar=${work}/inputs/velocity.jar" \
    "-PfloodgateApiVersion=${FLOODGATE_API_VERSION}" "-PfloodgateApiJar=${work}/inputs/floodgate-api.jar" \
    clean test jar
mapfile -t jars < <(find "${work}/gradle-build/libs" -maxdepth 1 -type f -name '*.jar')
[[ "${#jars[@]}" == 1 && "${jars[0]}" == */justvoxel-lobby.jar ]]
install -m0644 "${jars[0]}" "${output}/artifacts/justvoxel-lobby.jar"
cp -a "${work}/gradle-build/test-results" "${output}/metadata/"

# Retain corresponding LimboAPI source at the committed revision, never the mutable tag.
limbo_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_commit"])' "${package_dir}/limboapi-update.json")"
git init "${work}/limbo-source"
git -C "${work}/limbo-source" remote add origin https://github.com/Elytrium/LimboAPI.git
git -C "${work}/limbo-source" fetch --depth=1 origin "${limbo_commit}"
git -C "${work}/limbo-source" checkout --detach FETCH_HEAD
[[ "$(git -C "${work}/limbo-source" rev-parse HEAD)" == "${limbo_commit}" ]]
git -C "${work}/limbo-source" -c protocol.file.allow=never submodule update --init --recursive --depth=1
grep -Fq 'GNU AFFERO GENERAL PUBLIC LICENSE' "${work}/limbo-source/LICENSE"
cp "${work}/limbo-source/LICENSE" "${output}/licenses/LimboAPI-AGPL-3.0-only.txt"
tar --exclude='.git' -C "${work}" -czf "${output}/source/limboapi-${limbo_commit}.tar.gz" limbo-source
cp -a "${package_dir}/velocity-lobby" "${output}/source/"
rm -f "${output}/source/velocity-lobby/.gitignore"
cp "${package_dir}/velocity-lobby/LICENSE" "${output}/licenses/JustVoxel-Lobby-Apache-2.0.txt"
cp "${package_dir}/"*.py "${package_dir}/build.sh" "${package_dir}/package.env" "${package_dir}/limboapi-update.json" "${output}/source/"
cp "${package_dir}/package.env" "${output}/metadata/package.env"
printf '%s\n' "${GITHUB_SHA:-$(git -C "${root}" rev-parse HEAD)}" > "${output}/metadata/hsp-commit.txt"
java -version 2> "${output}/metadata/java-version.txt"
# Preserve license and notice material carried by the redistributed upstream JAR.
python3 - "${output}" <<'PY'
from pathlib import Path
import sys
import zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / 'artifacts/limboapi.jar') as jar:
    for index, name in enumerate(jar.namelist()):
        if not name.endswith('/') and any(word in name.upper() for word in ('LICENSE', 'NOTICE', 'COPYING')):
            (root / 'licenses' / f'limboapi-{index}-{Path(name).name}').write_bytes(jar.read(name))
PY
(
    cd "${output}"
    find artifacts metadata source licenses -type f ! -path metadata/SHA256SUMS -print0 \
        | sort -z | xargs -0 sha256sum > metadata/SHA256SUMS
    sha256sum --check metadata/SHA256SUMS
)
python3 "${package_dir}/validate.py" "${output}"
