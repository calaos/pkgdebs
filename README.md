# pkgdebs

Debian packaging for the Calaos-OS packages. Calaos-OS is the Debian
(bookworm) based distribution of the [Calaos](https://calaos.fr) home
automation suite. Most packages here do not ship the application itself: they
ship a systemd unit plus helper scripts that run an OCI container with
podman, and pull the container image on install.

## Packages

Each top-level directory is one source package with its own `debian/` and
`Makefile`. The directory name is what you pass to the build; the Debian
package name is in `debian/control` and can differ.

| Directory | Package | What it is | Default image / source |
|---|---|---|---|
| `calaos-meta` | `calaos` | Meta package pulling the whole Calaos-OS stack | none |
| `calaos-keyring` | `calaos-keyring` | APT sources (`/etc/apt/sources.list.d/calaos.list`) and the archive signing key; the key is downloaded from `deb.calaos.fr` at build time | none |
| `calaos-server` | `calaos-server` | Calaos main server (container) | `ghcr.io/calaos/calaos_base:$(VERSION)` |
| `calaos-home` | `calaos-home` | Calaos Home touchscreen GUI (container) | `ghcr.io/calaos/calaos_home:$(VERSION)` |
| `calaos-web-app` | `calaos-web-app` | Prebuilt static web UI into `/usr/share/calaos/webapp`, mounted read-only into the server container | tarball from the `calaos/calaos-web-app` GitHub release |
| `envoy` | `calaos-envoy` | Enphase Envoy service (container) | `ghcr.io/raoulh/envoy:$(VERSION)` |
| `grafana` | `calaos-grafana` | Grafana (container) | `docker.io/grafana/grafana:$(VERSION)` |
| `haproxy` | `calaos-haproxy` | HAProxy (container) | `docker.io/library/haproxy:$(VERSION)-alpine` |
| `hue2mqtt` | `calaos-hue2mqtt` | Philips Hue to MQTT bridge (container) | `ghcr.io/calaos/hue2mqtt:$(VERSION)` |
| `influxdb` | `calaos-influxdb` | InfluxDB (container) | `docker.io/library/influxdb:$(VERSION)-alpine` |
| `mosquitto` | `calaos-mosquitto` | Mosquitto MQTT broker (container) | `docker.io/library/eclipse-mosquitto:$(VERSION)` |
| `zigbee2mqtt` | `calaos-zigbee2mqtt` | Zigbee2MQTT (container) | `docker.io/koenkk/zigbee2mqtt:$(VERSION)` |

All packages are `Architecture: all`. Container packages depend on `podman`
and `calaos-container`. `calaos-container`, `calaos-ddns` and the remote UI
packages are not built here; the keyring points at their own apt
repositories (see `calaos-keyring/calaos.list`).

How the container packages work:

- `Makefile` `build` writes `container.source` (`IMAGE_SRC=...`,
  `SERVICE_NAME=...`), installed as `/usr/share/calaos/<package>.source`.
- The systemd unit loads that file as `EnvironmentFile` and starts the
  container (`start_calaos_server`, `start_calaos_home`, `start_z2mqtt`, or
  podman directly in the unit).
- `postinst` calls `pull_calaos_image`, a helper that is not defined in this
  repository (presumably provided by the `calaos-container` dependency).
- `*_pre` scripts (haproxy, mosquitto, hue2mqtt, envoy, zigbee2mqtt) create
  default config under `/mnt/calaos/...` and config templates go to
  `/usr/share/calaos/conf-template/` (envoy, hue2mqtt).
- Units are installed enabled for calaos-server, calaos-home, haproxy and
  mosquitto; envoy, grafana, hue2mqtt, influxdb and zigbee2mqtt use
  `--no-enable`.

## Building a package

Builds run in a Debian bookworm container (image `calaos-os-builder`, defined
by `Dockerfile`: devscripts, debhelper, lintian, fakeroot, ...). Docker is the
only host requirement.

```
make                                   # list commands
make docker-init                       # (re)build the builder image
make build-calaos-server PKGVERSION=4.5.0
make build-grafana PKGVERSION=11.6.0 IMAGE_SRC=docker.io/grafana/grafana:11.6.0
make docker-shell                      # shell in the builder
```

`build-<dir>` runs `/build_deb <dir> <PKGVERSION> <IMAGE_SRC>` in the
container (privileged, repo mounted at `/src` and `/work`). `build_deb`:

1. converts the first `-` of the version to `~` (e.g. `3.0.2-dev.0` becomes
   `3.0.2~dev.0`);
2. replaces the `1.2.3` placeholder in `debian/changelog` and the `VERSION`
   default in the package `Makefile`, and `IMAGE_SRC` if one was given;
3. runs `apt-get build-dep`, `dpkg-buildpackage -us -uc -b` and `lintian`;
4. runs `make clean` and moves the `.deb` to `pkg/` at the repo root.

`PKGVERSION` is required. `NOCACHE=1` forces a rebuild of the image without
Docker cache. The `.deb` files are unsigned; the apt repository does the
signing.

## Publishing

Nothing is published by a push or a pull request: there is no `push` trigger.
Two GitHub Actions workflows build and release:

- `.github/workflows/build_deb.yml`: triggered by a `repository_dispatch` event
  of type `build_deb` with `client_payload` fields `pkgname`, `version`,
  `image_src`, `prerelease`. Used to trigger builds from other repositories.
- `.github/workflows/build_deb_manual.yml`: `workflow_dispatch` with inputs
  `pkgname` (a choice list), `version`, `image_src` (required), `prerelease`.

Both run `make build-<pkgname> PKGVERSION=... IMAGE_SRC=...`, upload `pkg/*.deb`
as a workflow artifact, create a GitHub Release tagged `<pkgname>-<version>`
(with the `.deb` attached), then call a webhook (`DEB_REPO_WEBHOOK_URL`) to
refresh the apt repository. Secrets used: `CALAOS_REL_TOKEN`,
`DEB_REPO_WEBHOOK_URL`, `DEB_REPO_WEBHOOK_SECRET`. The apt repository itself
(`https://deb.calaos.fr/calaos/pkgdebs`, suite `bookworm`, as configured in
`calaos-keyring/calaos.list`) is managed outside this repository. It files a
GitHub prerelease under the `pre-releases` component and any other release
under `releases`; the keyring only lists `releases`.

## Releasing Calaos OS

The Calaos OS version shown on a box is the version of the `calaos` meta
package (`calaos-meta`). It is calendar based:

| Channel | Format | Example |
|---|---|---|
| stable | `YYYY.MM`, or `YYYY.MM.N` (N >= 1) for another release in the same month | `2026.11`, `2026.11.1` |
| dev | `YYYY.MM~dev.N` (the git tag uses `-dev.N`) | `2026.12~dev.0` |

Bump it only when a set of component releases is published, by running the
**Release Calaos OS** workflow (`.github/workflows/release_calaos_os.yml`,
Actions tab, from `main`) with the `version` and the `channel`. It:

1. refuses a version that does not match the channel format, or that is not
   strictly greater (`dpkg --compare-versions`) than the latest `calaos`
   published in the channel;
2. reads the apt indexes of every repository in `calaos-keyring/calaos.list`
   (component `releases` for stable, `releases` and `pre-releases` for dev,
   so that a stable release newer than every pre-release still wins), and
   takes the highest version of each package;
3. pins every `calaos-*` entry of `calaos-meta/debian/control` to
   `(>= <that version>)`, and writes a changelog entry listing those
   versions, which is also the release note; `ola` and `chrony` stay
   unversioned;
4. builds the deb, creates the release `calaos-meta-<version>` (a
   prerelease for dev) and refreshes the apt repository.

A `calaos-*` package listed in `Depends` but absent from the channel stops
the release. `dry_run` builds the deb as an artifact and publishes nothing:
use it to check the generated `Depends` first. A dev release should be
started once the component prereleases it needs are in the apt repository;
a stable one once their stable releases are.

The same steps run locally, without network, from fetched indexes:

```
./calaos_os_release fetch dev calaos-keyring/calaos.list apt-index
./calaos_os_release prepare dev 2026.12~dev.0 apt-index calaos-meta notes.md
make test        # offline tests of calaos_os_release, in the builder image
```

`prepare` rewrites `calaos-meta/debian/{control,changelog}` in place: do not
commit the result. Do not build `calaos-meta` with the generic workflows,
which publish it without pins.

## Adding or bumping a package

Bump: the version is not stored in the repo. Trigger a build with the new
`version` (and `image_src` if the image tag is not `$(VERSION)`). Edit the
package directory only to change packaging itself.

Add: copy a similar directory (for example `mosquitto` for a container
service), then:

1. adjust `debian/control` (`Package`, `Depends`), `Makefile` (`PKGNAME`,
   default `IMAGE_SRC`, `install` target), the systemd unit, `postinst`;
2. keep the `1.2.3` placeholder in `debian/changelog`, which `build_deb`
   substitutes;
3. add the directory to the `pkgname` options in
   `.github/workflows/build_deb_manual.yml`;
4. add the package to the `Depends` of `calaos-meta/debian/control` if it
   must be part of a default install, without a version: the Release Calaos
   OS workflow adds the bound;
5. test with `make build-<dir> PKGVERSION=0.0.1`.

## License

Packaging files declare GPL-3.0+ in each `debian/copyright` (Calaos Team);
`hue2mqtt/debian/copyright` additionally carries an MIT notice (Dan
Trickey). There is no top-level LICENSE file.
