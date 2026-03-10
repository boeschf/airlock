PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBEXECDIR ?= $(PREFIX)/libexec/airlock
DOCDIR ?= $(PREFIX)/share/doc/airlock
SYSCONFDIR ?= /etc/airlock

BIN_FILES := bin/airlock bin/airlock-firefox

# Executable helpers (invoked directly)
LIBEXEC_EXEC := \
	libexec/airlock/mountns-helper.sh \
	libexec/airlock/exec-with-env0.sh \
	libexec/airlock/refuse_root.sh

# Library scripts (sourced)
LIBEXEC_LIB := \
	libexec/airlock/common.sh \
	libexec/airlock/cli-utils.sh

DOC_FILES := README.md

TEST_FILES := $(shell find tests -type f 2>/dev/null)
SH_FILES := $(BIN_FILES) $(LIBEXEC_EXEC) $(LIBEXEC_LIB)

.PHONY: all install uninstall install-examples test shellcheck

all:
	@printf 'Nothing to build. Use make install or make test.\n'

install:
	install -d \
		$(DESTDIR)$(BINDIR) \
		$(DESTDIR)$(LIBEXECDIR) \
		$(DESTDIR)$(DOCDIR) \
		$(DESTDIR)$(SYSCONFDIR)

	install -m 755 $(BIN_FILES) $(DESTDIR)$(BINDIR)
	install -m 755 $(LIBEXEC_EXEC) $(DESTDIR)$(LIBEXECDIR)
	install -m 644 $(LIBEXEC_LIB) $(DESTDIR)$(LIBEXECDIR)

	install -m 644 $(DOC_FILES) $(DESTDIR)$(DOCDIR)

uninstall:
	rm -f \
		$(DESTDIR)$(BINDIR)/airlock \
		$(DESTDIR)$(BINDIR)/airlock-firefox

	rm -f \
		$(DESTDIR)$(LIBEXECDIR)/mountns-helper.sh \
		$(DESTDIR)$(LIBEXECDIR)/exec-with-env0.sh \
		$(DESTDIR)$(LIBEXECDIR)/refuse_root.sh \
		$(DESTDIR)$(LIBEXECDIR)/common.sh \
		$(DESTDIR)$(LIBEXECDIR)/cli-utils.sh

	rm -f \
		$(DESTDIR)$(DOCDIR)/README.md

	# Remove empty dirs (best-effort)
	rmdir --ignore-fail-on-non-empty \
		$(DESTDIR)$(LIBEXECDIR) \
		$(DESTDIR)$(DOCDIR) \
		$(DESTDIR)$(SYSCONFDIR) \
		2>/dev/null || true
