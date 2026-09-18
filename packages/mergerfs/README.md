# mergerfs package

Home Server Project builds mergerfs directly from the verified upstream release source instead of consuming the generic upstream Enterprise Linux RPM.

Upstream: `https://github.com/trapexit/mergerfs`

License: ISC

## Why this package exists

AlmaLinux 10 supports both the normal x86-64 baseline and an x86-64-v2 compatibility architecture. Generic third-party EL10 RPMs are not automatically safe for x86-64-v2 hardware.

This package therefore builds mergerfs twice from the same exact upstream release:

- normal AlmaLinux 10 → `x86_64`
- AlmaLinux 10 x86-64-v2 → `x86_64_v2`

Both builds must pass unit, RPM, ELF, installation, and functional FUSE mount/read/write/unmount validation before publication.

## Published channels

- `ghcr.io/home-server-project/mergerfs:stable`
- `ghcr.io/home-server-project/mergerfs:stable-v2`

Each build also receives an immutable version tag.

## Updates

`package.env` records the exact current upstream version and tag commit for reproducibility. Renovate monitors upstream mergerfs tags and automatically updates both values when a newer stable release appears. Manual version monitoring is not required.

If an upstream release regresses, the package can be deliberately rolled back by pinning an earlier verified release.
