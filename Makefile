# Builds a patched bluetooth.ko for one kernel. Normally run by DKMS
# (see dkms.conf); can also be run by hand:  make KVER=$(uname -r)

KVER  ?= $(shell uname -r)
KDIR  ?= /lib/modules/$(KVER)/build
TOP   := $(CURDIR)
SRC   := $(TOP)/src
BTDIR := $(SRC)/net/bluetooth
PATCHES := $(sort $(wildcard $(TOP)/patches/*.patch))

all: module

$(BTDIR)/.patched: $(PATCHES)
	rm -rf $(SRC)
	bash $(TOP)/scripts/fetch-bluetooth-src.sh $(KVER) $(SRC)
	set -e; for p in $(PATCHES); do \
		echo "applying $$(basename $$p)"; \
		patch -d $(SRC) -p1 --fuzz=2 --no-backup-if-mismatch -i $$p; \
	done
	touch $@

module: $(BTDIR)/.patched
	$(MAKE) -C $(KDIR) M=$(BTDIR) modules
	bash $(TOP)/scripts/check-symvers.sh $(KDIR) $(BTDIR)

clean:
	rm -rf $(SRC)

.PHONY: all module clean
