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
(`https://deb.calaos.fr/calaos/pkgdebs`, suite `bookworm`, component
`releases`, as configured in `calaos-keyring/calaos.list`) is managed outside
this repository.

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
   must be part of a default install;
5. test with `make build-<dir> PKGVERSION=0.0.1`.

## License

Packaging files declare GPL-3.0+ in each `debian/copyright` (Calaos Team);
`hue2mqtt/debian/copyright` additionally carries an MIT notice (Dan
Trickey). There is no top-level LICENSE file.
