VERSION?=1.0.0
PKGNAME?=calaos-keyring
ARCHIVE_KEY_URL?=https://deb.calaos.fr/calaos/calaos-container/archive.key

TOP_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

.PHONY: all

all: build

build:
	@echo "Building package $(VERSION)"
	curl -fsSL $(ARCHIVE_KEY_URL) -o $(TOP_DIR)/archive.key
	gpg --batch --yes --dearmor -o $(TOP_DIR)/calaos-archive-keyring.gpg < $(TOP_DIR)/archive.key

clean:
	@rm -rf $(TOP_DIR)/pkg $(TOP_DIR)/build \
			$(TOP_DIR)/archive.key \
			$(TOP_DIR)/calaos-archive-keyring.gpg \
			$(TOP_DIR)/debian/.debhelper \
			$(TOP_DIR)/debian/$(PKGNAME) \
			$(TOP_DIR)/debian/$(PKGNAME).debhelper.log \
			$(TOP_DIR)/debian/$(PKGNAME).substvars \
			$(TOP_DIR)/debian/files \
			$(TOP_DIR)/debian/debhelper-build-stamp \
			$(TOP_DIR)/debian/$(PKGNAME).substvars \
			$(TOP_DIR)/debian/$(PKGNAME).postinst.debhelper \
			$(TOP_DIR)/debian/$(PKGNAME).postrm.debhelper \
			$(TOP_DIR)/debian/$(PKGNAME).prerm.debhelper \
			$(TOP_DIR)/debian/$(PKGNAME).preinst.debhelper \
			$(TOP_DIR)/debian/$(PKGNAME).md5sums \
			$(TOP_DIR)/debian/$(PKGNAME).ex

deb:
	@echo "Building package $(VERSION)"
	@dpkg-buildpackage -us -uc -b

install:
	install -Dm644 calaos-archive-keyring.gpg $(DESTDIR)/usr/share/keyrings/calaos-archive-keyring.gpg
	install -Dm644 calaos.list $(DESTDIR)/etc/apt/sources.list.d/calaos.list
