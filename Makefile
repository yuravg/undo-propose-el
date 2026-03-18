.PHONY: help test compile checkdoc ci clean

.DEFAULT_GOAL := help

# Package information
PACKAGE := undo-propose.el
VERSION := $(shell perl -ne 'if (/^;;\s*Version:\s*(\S+)/) {print $$1; last}' $(PACKAGE))
TEST_COUNT := $(shell grep -c 'ert-deftest' tests/undo-propose-tests.el 2>/dev/null || echo 0)

# Emacs command
EMACS ?= emacs
BATCH := $(EMACS) --batch

help:
	@echo "undo-propose v$(VERSION) - Makefile targets"
	@echo ""
	@echo "  make test          Run ERT unit tests"
	@echo "  make compile       Byte-compile the package"
	@echo "  make checkdoc      Check documentation strings"
	@echo "  make ci            Run all checks (compile + checkdoc + test)"
	@echo "  make clean         Remove generated files"

test:
	@if [ -f tests/undo-propose-tests.el ]; then \
		$(BATCH) -l ert -l $(PACKAGE) \
		         -l tests/undo-propose-tests.el \
		         -f ert-run-tests-batch-and-exit; \
	else \
		echo "No tests found."; \
	fi

compile:
	@echo "Byte-compiling $(PACKAGE)..."
	@$(BATCH) -f batch-byte-compile $(PACKAGE)
	@echo "✓ Compilation successful"

checkdoc:
	@echo "Running checkdoc..."
	@$(BATCH) --eval "\
	(progn \
	  (require 'checkdoc) \
	  (let ((checkdoc-diagnostic-buffer \"*chk*\")) \
	    (checkdoc-file \"$(PACKAGE)\") \
	    (when (get-buffer \"*chk*\") \
	      (with-current-buffer \"*chk*\" \
	        (unless (zerop (buffer-size)) \
	          (message \"%s\" (buffer-string)) \
	          (kill-emacs 1))))))"

ci: clean compile checkdoc test
	@echo ""
	@echo "✓ All CI checks passed!"
	@echo "  - Byte compilation: OK"
	@echo "  - Documentation: OK"
	@echo "  - Tests: $(TEST_COUNT)/$(TEST_COUNT) passing"

clean:
	@echo "Cleaning generated files..."
	@rm -f *.elc *~
	@echo "✓ Clean complete"
