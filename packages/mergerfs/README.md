# mergerfs x86-64-v2 package

Home Server Project builds mergerfs directly from verified upstream source specifically for the AlmaLinux 10 x86-64-v2 compatibility architecture.

Upstream: `https://github.com/trapexit/mergerfs`

License: ISC

## Why this package exists

Generic third-party Enterprise Linux 10 RPMs are not automatically safe for x86-64-v2 hardware. Rose-v2 therefore needs a mergerfs RPM built in the AlmaLinux 10 x86-64-v2 environment.

This package builds only:

- AlmaLinux 10 x86-64-v2 → `x86_64_v2`

Normal Rose continues to use its existing mergerfs path and is outside the scope of this package work.

The v2 build must pass unit, RPM, ELF, installation, and functional FUSE mount/read/write/unmount validation before publication.

## Published channel

`ghcr.io/home-server-project/mergerfs:stable-v2`

Immutable releases use tags such as:

`2.42.0-1.hsp-v2`

## Updates

`package.env` records the exact current upstream version and tag commit for reproducibility. Renovate monitors upstream mergerfs tags and automatically updates both values when a newer stable release appears. Manual version monitoring is not required.

If an upstream release regresses, the package can be deliberately rolled back by pinning an earlier verified release.
