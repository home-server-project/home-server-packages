# cockpit-upside

Home Server Project packaging for [UPSide](https://github.com/deviationist/cockpit-upside), the Cockpit frontend for Network UPS Tools.

The package uses the upstream RPM packaging rather than maintaining a Home Server Project fork of the application.

## Targets

- Fedora 44 — consumed by Home Server Gina
- AlmaLinux 10 / EL10 — consumed by Home Server Rose

Each target is built and tested in its own distribution environment. `noarch` describes CPU architecture only; it does not mean that a package built under Fedora is automatically treated as interchangeable with an EL10 build.

## License

UPSide declares `LGPL-2.1-or-later`. Publication is gated on the expected RPM license metadata and required license/legal-notice files being present.

See the repository-wide [`LICENSE_POLICY.md`](../../LICENSE_POLICY.md).
