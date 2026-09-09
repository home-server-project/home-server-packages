# Third-party license policy

This repository redistributes third-party software only when its upstream license permits redistribution.

For every packaged project:

- Record the upstream project URL, release version, exact source commit, and declared SPDX license.
- Preserve the upstream copyright notices and license text required by that license.
- Include required license files in the binary package or published artifact.
- Retain the corresponding upstream source used for each published binary artifact when copyleft terms require source availability.
- Reject publication when the upstream project has no usable license, the license changed unexpectedly, or redistribution requirements are not understood.
- Treat custom, source-available, non-commercial, or otherwise unusual licenses as requiring manual review before publication.

## UPSide

Upstream: `https://github.com/deviationist/cockpit-upside`

Declared license: `LGPL-2.1-or-later`.

The RPM build must include the upstream `LICENSE` file and the generated JavaScript legal notice (`dist/index.js.LEGAL.txt`). The corresponding source used to build every published UPSide RPM must be retained with the published artifact.

## Superfile

Upstream: `https://github.com/yorukot/superfile`

Declared license: `MIT`.

The RPM build must include the upstream `LICENSE` file and `NOTICE.md`. The notice file is maintained upstream for bundled Go dependency notices and must be preserved with the binary package and published artifact. The exact upstream source used for each published Superfile RPM is retained for provenance.

## VirtUI Manager

Upstream: `https://github.com/aginies/virtui-manager`

Declared license: `GPL-3.0-or-later`.

The RPM build must include the upstream `LICENSE` file and retain the exact corresponding upstream source used for every published VirtUI Manager RPM.

VirtUI Manager also carries a private, architecture-independent Python dependency tree for Textual under `/usr/libexec/virtui-manager/python`. The dependency declaration and `uv.lock` are retained with the published source artifact. Every locked private dependency must have an expected SPDX entry in `packages/virtui-manager/python/python-licenses.tsv`, and license material from each installed wheel must be retained in the RPM and published artifact. A missing license entry, missing wheel license file, unexpected dependency, or architecture-specific wheel blocks publication.
