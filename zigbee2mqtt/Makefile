VERSION?=1.0.0
PKGNAME?=calaos-zigbee2mqtt
IMAGE_SRC?=docker.io/koenkk/zigbee2mqtt:$(VERSION)

TOP_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

.PHONY: all

all: build

build:
	@echo "Building package $(VERSION)"
	@echo "Using image: $(IMAGE_SRC)"
	@echo "IMAGE_SRC=$(IMAGE_SRC)" > $(TOP_DIR)/container.source

clean:
	@rm -rf $(TOP_DIR)/pkg $(TOP_DIR)/build \
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
			$(TOP_DIR)/debian/$(PKGNAME).ex \
			$(TOP_DIR)/container.source

deb:
	@echo "Building package $(VERSION)"
	@dpkg-buildpackage -us -uc -b

install:
	install -Dm755 zigbee2mqtt_pre $(DESTDIR)$(PREFIX)/sbin/zigbee2mqtt_pre
	install -Dm755 start_z2mqtt $(DESTDIR)$(PREFIX)/sbin/start_z2mqtt
	install -Dm644 container.source $(DESTDIR)$(PREFIX)/usr/share/calaos/$(PKGNAME).source
