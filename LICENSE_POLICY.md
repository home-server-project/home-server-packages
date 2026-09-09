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
