.PHONY: check test

check: test
	@for file in bin/* lib/*.sh tests/*.sh install.sh; do \
		[ -e "$$file" ] || continue; \
		/bin/sh -n "$$file" || exit 1; \
	done

test:
	@/bin/sh tests/run.sh
