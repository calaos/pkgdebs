VERSION?=1.0.0
PKGNAME?=calaos-web-app

# build_deb hands the version over already debianized (the first dash is
# turned into a tilde, e.g. 3.0.2-dev.0 -> 3.0.2~dev.0) while the upstream
# git tag / release asset keeps the dash. Rebuild the tag from the version.
TAG=$(subst ~,-,$(VERSION))
TARBALL_URL?=https://github.com/calaos/calaos-web-app/releases/download/$(TAG)/calaos-web-app-$(TAG).tar.gz

TOP_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR := $(TOP_DIR)build
STAGE_DIR := $(BUILD_DIR)/webapp
TARBALL := $(BUILD_DIR)/calaos-web-app.tar.gz
WEBAPP_DIR := /usr/share/calaos/webapp

.PHONY: all build clean deb install

all: build

build:
	@echo "Building package: $(VERSION)"
	@echo "Fetching $(TARBALL_URL)"
	@mkdir -p $(STAGE_DIR)
	curl -fL --retry 3 --retry-delay 2 -o $(TARBALL) "$(TARBALL_URL)"
	tar -xzf $(TARBALL) -C $(STAGE_DIR)
	@test -f $(STAGE_DIR)/index.html || \
		{ echo "ERROR: index.html not found at the root of $(TARBALL_URL)"; exit 1; }

clean:
	@rm -rf $(TOP_DIR)pkg $(BUILD_DIR) \
			$(TOP_DIR)debian/.debhelper \
			$(TOP_DIR)debian/$(PKGNAME) \
			$(TOP_DIR)debian/$(PKGNAME).debhelper.log \
			$(TOP_DIR)debian/$(PKGNAME).substvars \
			$(TOP_DIR)debian/files \
			$(TOP_DIR)debian/debhelper-build-stamp \
			$(TOP_DIR)debian/$(PKGNAME).postinst.debhelper \
			$(TOP_DIR)debian/$(PKGNAME).postrm.debhelper \
			$(TOP_DIR)debian/$(PKGNAME).prerm.debhelper \
			$(TOP_DIR)debian/$(PKGNAME).preinst.debhelper \
			$(TOP_DIR)debian/$(PKGNAME).md5sums \
			$(TOP_DIR)debian/$(PKGNAME).ex

deb:
	@echo "Building package $(VERSION)"
	@dpkg-buildpackage -us -uc -b

install:
	install -d $(DESTDIR)$(WEBAPP_DIR)
	cp -r $(STAGE_DIR)/. $(DESTDIR)$(WEBAPP_DIR)/
	find $(DESTDIR)$(WEBAPP_DIR) -type d -exec chmod 0755 {} +
	find $(DESTDIR)$(WEBAPP_DIR) -type f -exec chmod 0644 {} +
