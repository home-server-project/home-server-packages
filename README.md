# Home Server Packages

Third-party package build and validation repository for the Home Server Project.

This repository builds software that is not consumed directly from the Fedora or AlmaLinux repositories but is required by Home Server Project images. Each package keeps its upstream source, license, build, test, and publication handling isolated from the operating-system image repositories.

## Current status

Implemented package pipelines:

- UPSide (`deviationist/cockpit-upside`)
- Superfile (`yorukot/superfile`)

Planned later:

- VirtUI Manager
- shared orchestration/validation workflow after the individual package pipelines are proven

## Policy

- Upstream releases and exact source commits are tracked automatically.
- Package updates must build and pass their required distro tests before automatic promotion.
- Fedora and Enterprise Linux artifacts are built/tested independently when their environments differ.
- A single package artifact may serve both Fedora and Enterprise Linux only after the exact same artifact passes both validation environments.
- Third-party licenses and required notices remain with the package artifacts.
- Corresponding source is retained with published artifacts when required by license terms and when useful for provenance.
- No package version maintenance belongs in Gina, Rose, or other consuming image repositories.

See [`LICENSE_POLICY.md`](LICENSE_POLICY.md) for the repository's third-party licensing rules.
