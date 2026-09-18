# mergerfs x86-64-v2 package

Home Server Project builds mergerfs from an exact verified upstream release and commit for AlmaLinux 10 x86-64-v2.

Upstream: `https://github.com/trapexit/mergerfs`

License: ISC

## Pipeline

This package follows the same repository pattern as the other Home Server Packages:

1. Build and run upstream tests.
2. Package the built payload into an RPM.
3. Upload the exact RPM artifact.
4. Validate that exact RPM in the target environment.
5. Publish only after build and validation succeed.

The architecture-specific exception is the build and validation environment: AlmaLinux 10 is resolved explicitly as `linux/amd64/v2`, using the same v2 selection pattern proven by Home Server Base 10.

The package produced here is only `x86_64_v2`. Normal Rose continues to use its existing mergerfs path.

## Published channel

`ghcr.io/home-server-project/mergerfs:stable-v2`

Immutable releases use versioned tags such as `2.42.0-1.hsp-v2`.

## Updates

`package.env` records the exact upstream version and tag commit. Renovate monitors upstream mergerfs tags and updates both values automatically.
