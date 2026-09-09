# cockpit-upside

Home Server Project packaging for [UPSide](https://github.com/deviationist/cockpit-upside), the Cockpit frontend for Network UPS Tools.

UPSide is built from an exact verified upstream release and commit. The Home Server Project then packages the generated static Cockpit bundle into a small neutral `noarch` RPM instead of relying on UPSide's upstream RPM target.

## Build model

1. Build the UPSide static bundle once in Fedora 44 using the same `make` path already used by Home Server images.
2. Package the generated `dist/` bundle, metainfo, README, upstream license, and generated JavaScript legal notice into one Home Server Project RPM.
3. Record the exact RPM SHA256.
4. Install and validate that exact same RPM on:
   - Fedora 44, for Home Server Gina
   - AlmaLinux 10 / EL10, for Home Server Rose
5. Publish the universal package only if both validation targets pass.

If future testing proves that Fedora and EL require different packaging, this package can split into distro-specific variants without changing the repository layout or upstream tracking model.

## Why not use upstream `make rpm`?

UPSide 1.0.6's RPM path currently assumes a `po/` translation directory that is not present in the project, and its install target can also rebuild the JavaScript bundle in environments where the RPM spec expects to use the pre-built bundle. The Home Server package therefore uses the already-proven static-bundle build path and keeps RPM packaging intentionally small.

## License

UPSide declares `LGPL-2.1-or-later`.

Every published artifact retains:

- exact upstream source snapshot
- exact upstream commit
- upstream `LICENSE`
- generated `dist/index.js.LEGAL.txt`
- Home Server RPM packaging recipe
- SHA256 metadata

Publication is gated on the expected RPM license metadata and required license/legal-notice files being present.

See the repository-wide [`LICENSE_POLICY.md`](../../LICENSE_POLICY.md).
