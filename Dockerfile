#Docker image used to build the deb

FROM debian:bookworm

RUN apt -y update && \
    apt -y upgrade && \
    apt-get install -yq --no-install-recommends devscripts debhelper dpkg-dev fakeroot lintian sudo \
        pkgconf git python3-semver python3-git lintian

COPY build_deb /build_deb
COPY  get_last_tag.py /get_last_tag.py