# VirtUI Manager package

Upstream: `aginies/virtui-manager`

VirtUI Manager is packaged once as a Home Server Project `noarch` RPM and the exact same RPM is validated on Fedora 44 and AlmaLinux 10 before publication.

## Source and dependency model

- The upstream release tag and exact commit are both verified before building.
- VirtUI Manager itself is installed from that exact source without resolving its Python dependencies through pip.
- Textual and its portable Python dependency closure live privately under `/usr/libexec/virtui-manager/python`.
- The private dependency tree is declared by `python/pyproject.toml` and locked by `python/uv.lock`.
- Normal builds consume the committed lock in frozen mode and require the recorded wheel hashes.
- Native integrations such as libvirt Python bindings, PyGObject, netifaces, PyYAML and requests remain distro packages.
- The private Python tree must remain architecture-independent; ELF files are rejected during the package build.

The initial Textual baseline is `8.2.3`, matching the dependency set used by the official VirtUI Manager v3.3.2 Flatpak build. Renovate tracks Textual automatically and refreshes `uv.lock`; lock-file maintenance also updates compatible transitive dependencies. Updates promote automatically only after the complete package workflow succeeds.

## Validation

The package pipeline runs upstream consistency checks and tests, builds one RPM, then validates that exact RPM on:

- Fedora 44
- AlmaLinux 10

Validation includes package checksum, installation, command/import checks, exact VirtUI/Textual versions, private Python architecture checks and `rpm -V`.

## Licensing

VirtUI Manager is GPL-3.0-or-later. The exact upstream source is retained with every published artifact. Licenses for the private Python dependency bundle are copied into the RPM and published artifact and are checked against `python/python-licenses.tsv`.
