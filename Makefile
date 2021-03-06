Version=17.0

PREFIX = /usr/local
SYSCONFDIR = /etc

BIN = \
	bin/manjaro-live \
	bin/mhwd-live \
	bin/mhwd-live-net

XBIN = \
	bin/desktop-items \
	bin/disable-dpms \
	bin/pulseaudio-ctl-normal

XDG = $(wildcard data/*.desktop)

LIBS = $(wildcard lib/*.sh)

SHARED = \
	$(wildcard data/*.map) \
	data/live.conf

RC = \
	data/rc/gnupg-mount \
	data/rc/mhwd-live-net \
	data/rc/mirrors-live-net \
	data/rc/pacman-init \
	data/rc/manjaro-live \
	data/rc/mhwd-live \
	data/rc/mirrors-live

SD = $(wildcard data/sd/*)

GRUB_DEFAULT = \
	data/grub2-portable-efi

GRUB_D = \
	data/99_zzz-portable-efi

all: $(BIN) $(RC) $(XBIN) ${GRUB_D}

edit = sed -e "s|@datadir[@]|$(DESTDIR)$(PREFIX)/share/manjaro-tools|g" \
	-e "s|@sysconfdir[@]|$(DESTDIR)$(SYSCONFDIR)/manjaro-tools|g" \
	-e "s|@libdir[@]|$(DESTDIR)$(PREFIX)/lib/manjaro-tools|g"

%: %.in Makefile
	@echo "GEN $@"
	@$(RM) "$@"
	@m4 -P $@.in | $(edit) >$@
	@chmod a-w "$@"
	@chmod +x "$@"

clean:
	rm -f $(BIN) $(RC) $(XBIN) ${GRUB_D}

install_base:
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${BIN} $(DESTDIR)$(PREFIX)/bin

	install -dm0755 $(DESTDIR)$(PREFIX)/lib/manjaro-tools
	install -m0644 ${LIBS} $(DESTDIR)$(PREFIX)/lib/manjaro-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/manjaro-tools
	install -m0644 ${SHARED} $(DESTDIR)$(PREFIX)/share/manjaro-tools

install_rc:
	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/init.d
	install -m0755 ${RC} $(DESTDIR)$(SYSCONFDIR)/init.d

install_sd:
	install -dm0755 $(DESTDIR)$(PREFIX)/lib/systemd/system
	install -m0644 ${SD} $(DESTDIR)$(PREFIX)/lib/systemd/system

install_xdg:
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${XBIN} $(DESTDIR)$(PREFIX)/bin

	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/skel/.config/autostart
	install -m0755 ${XDG} $(DESTDIR)$(SYSCONFDIR)/skel/.config/autostart

install_portable_efi:
	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/default
	install -m0755 $(GRUB_DEFAULT) $(DESTDIR)$(SYSCONFDIR)/default

	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/grub.d
	install -m0755 $(GRUB_D) $(DESTDIR)$(SYSCONFDIR)/grub.d

uninstall_base:
	for f in ${BIN}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${SHARED}; do rm -f $(DESTDIR)$(PREFIX)/share/manjaro-tools/$$f; done
	for f in ${LIBS}; do rm -f $(DESTDIR)$(PREFIX)/lib/manjaro-tools/$$f; done

uninstall_portable_efi:
	for f in ${GRUB_DEFAULT}; do rm -f $(DESTDIR)$(SYSCONFDIR)/default/$$f; done
	for f in ${GRUB_D}; do rm -f $(DESTDIR)$(SYSCONFDIR)/grub.d/$$f; done

uninstall_rc:
	for f in ${RC}; do rm -f $(DESTDIR)$(SYSCONFDIR)/init.d/$$f; done

uninstall_sd:
	for f in ${SD}; do rm -f $(DESTDIR)$(PREFIX)/lib/systemd/system/$$f; done

uninstall_xdg:
	for f in ${XBIN}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${XDG}; do rm -f $(DESTDIR)$(SYSCONFDIR)/skel/.config/autostart/$$f; done

install: install_base install_rc install_sd install_xdg install_portable_efi

uninstall: uninstall_base uninstall_rc uninstall_sd uninstall_xdg uninstall_portable_efi

dist:
	git archive --format=tar --prefix=manjaro-tools-livecd-$(Version)/ $(Version) | gzip -9 > manjaro-tools-livecd-$(Version).tar.gz
	gpg --detach-sign --use-agent manjaro-tools-livecd-$(Version).tar.gz

.PHONY: all clean install uninstall dist
