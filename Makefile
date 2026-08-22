.PHONY: check install uninstall

check:
	./tests/check.sh

install:
	./install.sh

uninstall:
	./uninstall.sh --uninstall
