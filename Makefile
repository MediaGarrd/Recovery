SHELL := bash
SHELLFILES := mgrecover.sh $(wildcard tests/*.sh)

define need
@command -v $(1) >/dev/null || { echo "missing tool: $(1) (Debian/Ubuntu: apt install $(2); Arch: pacman -S $(3))" >&2; exit 1; }
endef

.NOTPARALLEL:
.PHONY: test check-tools lint unit sim

test: check-tools lint unit sim

check-tools:
	$(call need,shellcheck,shellcheck,shellcheck)
	$(call need,bwrap,bubblewrap,bubblewrap)
	$(call need,bsdtar,libarchive-tools,libarchive)
	$(call need,python3,python3,python)

lint:
	$(call need,shellcheck,shellcheck,shellcheck)
	shellcheck -x -P SCRIPTDIR $(SHELLFILES)

unit:
	$(call need,bsdtar,libarchive-tools,libarchive)
	$(call need,python3,python3,python)
	bash tests/unit.sh

sim:
	$(call need,bwrap,bubblewrap,bubblewrap)
	$(call need,bsdtar,libarchive-tools,libarchive)
	$(call need,python3,python3,python)
	bash tests/sim-root.sh
	bash tests/sim-sandbox.sh
