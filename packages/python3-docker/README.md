# python3-docker

Home Server Project package for the Docker SDK for Python.

Upstream: `docker/docker-py`

The package is pure Python and produces `noarch` RPMs, but Fedora 44 and
AlmaLinux 10 use different Python ABIs. The same verified upstream source is
therefore built independently in both target environments:

- Fedora 44 -> `python3-docker-*.fc44.noarch.rpm`
- AlmaLinux 10 -> `python3-docker-*.el10.noarch.rpm`

Both RPMs are published together in:

`ghcr.io/home-server-project/python3-docker:stable`

Consumers use the `:stable` package artifact and select the RPM matching
their operating system. Runtime dependencies such as Requests and urllib3
come from the target distribution; no private Python dependency tree is
bundled.

The build verifies the upstream release tag against the exact pinned commit,
builds a normal RPM with the target distribution's Python, validates import
and version metadata in a clean target container, preserves the upstream
Apache-2.0 license, and retains the exact source used for the package.
