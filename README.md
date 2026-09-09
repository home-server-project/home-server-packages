# Home Server Packages

Third-party package build and validation repository for the Home Server Project.

This repository builds software that is not consumed directly from the Fedora or AlmaLinux repositories but is required by Home Server Project images. Each package keeps its upstream source, license, build, test, and publication handling isolated from the operating-system image repositories.

## Current status

Development has started with **UPSide** (`deviationist/cockpit-upside`).

Planned later:

- Superfile
- VirtUI Manager
- shared orchestration/validation workflow after the individual package pipelines are proven

## Policy

- Upstream releases and exact source commits are tracked automatically.
- Package updates must build and pass their required distro tests before automatic promotion.
- Fedora and Enterprise Linux artifacts are built/tested independently when their environments differ.
- Third-party licenses and required notices remain with the package artifacts.
- Corresponding source is retained with published artifacts for redistributable copyleft software.
- No package version maintenance belongs in Gina, Rose, or other consuming image repositories.

See [`LICENSE_POLICY.md`](LICENSE_POLICY.md) for the repository's third-party licensing rules.
