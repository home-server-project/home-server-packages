# Home Server Packages

Central third-party package build, validation, and publication repository for the Home Server Project.

This repository builds software that is not consumed directly from the Fedora or AlmaLinux repositories but is required by Home Server Project images. Each package keeps its upstream source, license, build, test, and publication handling isolated from the operating-system image repositories.

## Packages

Implemented and published package pipelines:

- UPSide (`deviationist/cockpit-upside`)
- Superfile (`yorukot/superfile`)
- VirtUI Manager (`aginies/virtui-manager`)

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

The published stable package set is also validated together on:

- Fedora 44
- AlmaLinux 10 + EPEL

The shared validator does not rebuild packages. It pulls the exact published `:stable` artifacts, verifies their checksums and metadata, installs the package set together, and runs functional checks.

The scheduled validation runs every Friday at 22:45 UTC, before the weekly Gina and Rose image builds.

Current stable artifact channels:

```text
ghcr.io/home-server-project/cockpit-upside:stable
ghcr.io/home-server-project/superfile:stable
ghcr.io/home-server-project/virtui-manager:stable
```

Each package also publishes an immutable versioned tag.

## Automation

Upstream updates are automatic.

Exact upstream versions and commits, and private dependency locks where required, are maintained in this repository. A package update must build and pass its required validation before it is promoted to the stable channel.

The shared stable-package validation then checks the already-published package set against the current Fedora and AlmaLinux environments before the scheduled operating-system image builds.

## Consumers

Gina and Rose are intended to consume these verified packages instead of rebuilding the same third-party software from source inside their own image builds.

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
