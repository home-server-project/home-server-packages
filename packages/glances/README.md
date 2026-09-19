# Glances package

Home Server Project packaging for Glances, the system monitoring application used by JustVoxel System Monitor.

Upstream: `https://github.com/nicolargo/glances`

License: LGPL-3.0-only

## Build model

Glances is packaged for the JustVoxel AlmaLinux 10 base only.

The package follows the normal Home Server Packages pattern:

1. Verify the upstream release tag and exact commit.
2. Install only the Glances application from that exact source into a private architecture-independent path.
3. Use AlmaLinux 10 and EPEL packages for normal Python runtime dependencies instead of bundling a second dependency tree.
4. Build one noarch RPM.
5. Validate that exact RPM on AlmaLinux 10 + EPEL.
6. Publish only after validation succeeds.

The package intentionally does not carry the upstream `all` optional dependency set. JustVoxel will enable only the monitoring features it actually uses.

For container monitoring, the package uses AlmaLinux's distro `python3-podman` client. Glances can therefore use its native Podman engine without bundling a private Python client.

The upstream `pyinstrument` dependency is not bundled because it is used by Glances profiling/development tooling rather than the normal application/WebUI runtime. Package validation starts the real WebUI to make this omission an explicit tested condition.

## Published channel

`ghcr.io/home-server-project/glances:stable`

Immutable releases use versioned tags such as `4.5.6-1.hsp`.

## Updates

`package.env` records the exact upstream version and tag commit. Renovate watches Glances tags and updates both values together. CI rebuilds and validates the package before the updated stable artifact can be published.
