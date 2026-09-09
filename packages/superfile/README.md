# Superfile

Home Server Project packaging for [Superfile](https://github.com/yorukot/superfile), the terminal file manager installed as `spf`.

## Build model

Superfile is built from the exact verified upstream release tag and commit rather than repackaging the upstream release binary.

The upstream Linux build uses `CGO_ENABLED=0`, so the resulting x86_64 binary is packaged once and the exact same RPM is validated on:

- Fedora 44 — Home Server Gina target
- AlmaLinux 10 / EL10 — Home Server Rose target

A single RPM is published only when both validation jobs pass. If a future release proves distro-specific, the package layout can be split without changing the upstream version-tracking model.

## Updates

`package.env` is the source of truth for the upstream version and exact tag commit. Renovate watches `yorukot/superfile` releases and automatically updates both values together. CI then rebuilds, tests, validates and promotes the new package only when all required checks pass.

The Go toolchain follows the version declared by upstream in `go.mod` through Go's automatic toolchain selection.

## Runtime helpers

Superfile can optionally use external tools such as `ffmpeg`, `pdftoppm`, `exiftool`, `bat`, and `zoxide` for previews or plugins. They are not hard RPM requirements because the core file manager does not require all of them.

## License

Superfile declares the MIT license. The RPM and published artifact include:

- upstream `LICENSE`
- upstream `NOTICE.md`, which carries third-party dependency notices
- exact upstream source for provenance

See the repository-wide [`LICENSE_POLICY.md`](../../LICENSE_POLICY.md).
