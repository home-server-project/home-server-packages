# Playit package

Home Server Project packaging for the Playit agent used by JustVoxel.

Upstream: `https://github.com/playit-cloud/playit-agent`

License: BSD-2-Clause

## Build model

Playit is packaged for the JustVoxel AlmaLinux 10 x86_64 target only.

The package follows the normal Home Server Packages model:

1. Verify the stable upstream release tag and its exact commit.
2. Build the CLI and daemon from that exact source with the committed Cargo.lock.
3. Run the relevant upstream Rust test suites.
4. Build an AlmaLinux 10 x86_64 RPM using the upstream Linux service files.
5. Validate that exact RPM on AlmaLinux 10.
6. Publish only after validation succeeds.

The package does not consume Playit's upstream prebuilt RPM or release binaries.

## Service model

The RPM ships the Playit systemd service, sysusers definition, tmpfiles
configuration, logrotate configuration, and the upstream CLI wrapper.

Installing the RPM does not enable or start the service. This is deliberate:
Home Server Packages owns the software artifact, while JustVoxel owns appliance
policy.

The package validation proves both states:

- A freshly installed RPM is disabled and contains no Playit secret.
- The unit can be enabled without a secret, and an unconfigured daemon enters
  Playit's supported `waiting for secret` state.

When JustVoxel consumes this package later, JustVoxel should enable
`playit.service` during image composition but must not create
`/etc/playit/playit.toml`. The administrator's Playit setup then provisions
the secret after deployment.

## Published channel

`ghcr.io/home-server-project/playit:stable`

Immutable releases use versioned tags such as `1.0.10-1.hsp`.

## Updates

`package.env` records the current stable upstream version and exact tag commit.
Renovate watches upstream tags, ignores prereleases, and updates both values
together. CI must rebuild and validate the new package before the stable
artifact is published.
