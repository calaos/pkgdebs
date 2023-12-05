#Docker image used to build the deb

FROM debian:bookworm

RUN apt -y update && \
    apt -y upgrade && \
    apt-get install -yq --no-install-recommends devscripts debhelper dpkg-dev fakeroot lintian sudo \
        pkgconf git

COPY build_deb /build_deb