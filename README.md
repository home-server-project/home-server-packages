# Home Server Packages

Central shared package build, validation, and publication repository for the Home Server Project.

This repository builds first-party and third-party software that is not consumed directly from the Fedora or AlmaLinux repositories but is required by Home Server Project images. Each package keeps its upstream source, license, build, test, and publication handling isolated from the operating-system image repositories.

## Packages

Implemented and published package pipelines:

- UPSide (`deviationist/cockpit-upside`)
- Superfile (`yorukot/superfile`)
- mergerfs (`trapexit/mergerfs`) — AlmaLinux 10 x86-64-v2 compatibility build
- Glances (`nicolargo/glances`) — AlmaLinux 10 / JustVoxel system monitor package
- Playit (`playit-cloud/playit-agent`) — AlmaLinux 10 / JustVoxel game tunnel agent
- VirtUI Manager (`aginies/virtui-manager`)
- NetworkManager-HSP (`home-server-project/nm-hsp`) — x86_64 + aarch64
- python3-docker (`docker/docker-py`) — Fedora 44 + AlmaLinux 10 noarch builds
- Minecraft Network Plugins — LimboAPI and JustVoxel Lobby in a scratch OCI artifact

Each package keeps its own independent pipeline:

```text
upstream release
    ↓
exact source provenance
    ↓
build + upstream/package tests
    ↓
Fedora / Enterprise Linux validation
    ↓
immutable GHCR artifact
    ↓
:stable
```

## Stable package set

The published shared stable package set is also validated together on:

- Fedora 44
- AlmaLinux 10 + EPEL

The stable-package validator resolves every published package channel. Universal packages are validated on Fedora 44 and AlmaLinux 10. AlmaLinux-specific packages are validated only on their intended AlmaLinux target, including the x86-64-v2 mergerfs channel.

The shared validator does not rebuild packages. It pulls the exact published `:stable` artifacts, verifies their checksums and metadata, installs the package set together, and runs functional checks.

The scheduled validation runs every Friday at 22:45 UTC, before the weekly Gina and Rose image builds.

Current shared stable artifact channels:

```text
ghcr.io/home-server-project/cockpit-upside:stable
ghcr.io/home-server-project/superfile:stable
ghcr.io/home-server-project/virtui-manager:stable
ghcr.io/home-server-project/nm-hsp:stable
ghcr.io/home-server-project/python3-docker:stable
```

AlmaLinux-specific channels:

```text
ghcr.io/home-server-project/glances:stable
ghcr.io/home-server-project/playit:stable
ghcr.io/home-server-project/mergerfs:stable-v2
```

Minecraft plugin channel (validated directly as an OCI payload, without RPM installation):

```text
ghcr.io/home-server-project/minecraft-network-plugins:stable
```

Each package also publishes an immutable versioned tag. Minecraft Network Plugins publishes an immutable composition tag.

## Automation

Upstream updates are automatic.

Exact upstream versions and commits, and private dependency locks where required, are maintained in this repository. A package update must build and pass its required validation before it is promoted to its stable channel.

The shared stable-package validation then checks the already-published package set against the current Fedora and AlmaLinux environments before the scheduled operating-system image builds.

## Minecraft Network Plugins

Home Server Packages owns the maintained lobby source and build in
[`packages/minecraft-network-plugins/`](packages/minecraft-network-plugins/).
The runtime payload is `/artifacts/limboapi.jar` (LimboAPI) and
`/artifacts/justvoxel-lobby.jar` (JustVoxel Lobby), with `/metadata/`, `/source/`
and `/licenses/`. Velocity and Floodgate API are compile-only inputs for
JustVoxel Lobby and are never included in the runtime payload.

The LimboAPI updater discovers the latest normal stable GitHub Release and
resolves that release's exact tag to the exact full source commit. The historical
`dev-build` pin remains supported only for migration. Proposed dependency state
in `limboapi-update.json` remains exact and reviewable, including the release tag,
full source commit, release/asset identity, filename, publication time, size,
SHA-256, exact asset API URL, license and compatibility note. Builds never consume
`latest`. Changes arrive through the existing updater PR workflow, including the
old and new full commits. Compatibility still requires review when the source
commit changes.

Velocity uses only exact reviewed `VELOCITY_VERSION` + `VELOCITY_BUILD` in
`package.env` (initially 4.3.1 build 45). The build queries the official PaperMC
Fill API for that exact selection, requires STABLE, and verifies its official
artifact host, size and SHA-256. Only the updater discovers newer STABLE builds.
Floodgate API uses an exact timestamped 2.2.5 snapshot selection from official
OpenCollab Maven metadata. Its mutable `2.2.5-SNAPSHOT` coordinate is never
resolved by the build; the exact artifact is checked against OpenCollab's
SHA-256 sidecar and used only for compilation.

The scheduled or manually dispatched package updater proposes all three inputs
on a dedicated branch through a PR to `main`. Unchanged inputs produce no PR.
The updater never publishes. Package builds never choose newer versions.
The updater uses the built-in `GITHUB_TOKEN`, with only `contents: write` and
`pull-requests: write` granted to the job. The token is repository-scoped and
lasts only for the job; no persistent updater credential is stored.
CI for updater-created or updated PRs may require a repository user with write
access to click "Approve workflows to run". It writes only the two package state files;
its branch is `automation/minecraft-network-plugins`.
Java 25 builds run the lobby's Gradle tests using a checksum-verified Gradle
distribution. PRs build and validate the exact uploaded payload without publishing.
Package publishing happens only after the normal reviewed PR is merged to
`main` and the normal main build and validation succeed, publishing
`ghcr.io/home-server-project/minecraft-network-plugins:stable` and an immutable
composition tag. Published checksums, plugin identities and dependency
non-bundling are also checked by scheduled stable validation.

JustVoxel consumption of this channel will be switched in a separate task.

## Consumers

Gina, Rose, JustVoxel, and other Home Server Project products are intended to consume these verified packages instead of rebuilding shared software from source inside their own image builds.

This keeps responsibilities separate:

```text
home-server-packages
    = software factory

Gina / Rose
    = operating-system factory
```

## Policy

- Upstream releases and exact source commits are tracked automatically.
- Package updates must build and pass their required distro tests before automatic promotion.
- Fedora and Enterprise Linux artifacts are built/tested independently when their environments differ.
- A single package artifact may serve both Fedora and Enterprise Linux only after the exact same artifact passes both validation environments.
- Private bundled dependency trees must be locked and reproducible rather than resolved differently on each consumer-image build.
- Third-party licenses and required notices remain with the package artifacts.
- Corresponding source is retained with published artifacts when required by license terms and when useful for provenance.
- No package version maintenance belongs in Gina, Rose, or other consuming image repositories.

See [`LICENSE_POLICY.md`](LICENSE_POLICY.md) for the repository's third-party licensing rules.
