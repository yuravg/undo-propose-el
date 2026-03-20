.PHONY: help compile test checkdoc lint ci clean

.DEFAULT_GOAL := help

# Package information
PACKAGE := undo-propose
VERSION := $(shell perl -ne 'if (/^;;\s*Version:\s*(\S+)/) {print $$1; last}' $(PACKAGE).el)
TEST_COUNT := $(shell grep -c 'ert-deftest' tests/$(PACKAGE)-tests.el 2>/dev/null || echo 0)

# Emacs command
EMACS ?= emacs
BATCH := $(EMACS) --batch

# All Elisp source files
EL_FILES := $(PACKAGE).el $(wildcard tests/*.el)

help:
	@echo "$(PACKAGE) v$(VERSION) - Makefile targets"
	@echo ""
	@echo "Development:"
	@echo "  make compile       Byte-compile the package"
	@echo "  make clean         Remove generated files"
	@echo ""
	@echo "Quality checks:"
	@echo "  make test          Run ERT unit tests ($(TEST_COUNT) tests)"
	@echo "  make checkdoc      Check documentation strings"
	@echo "  make lint          Run package-lint (requires network)"
	@echo ""
	@echo "CI:"
	@echo "  make ci            Run all"
	@echo ""

$(PACKAGE).elc: $(PACKAGE).el
	@echo "Byte-compiling $(PACKAGE)..."
	@$(BATCH) --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(PACKAGE).el
	@echo "✓ Compilation successful"

compile: $(PACKAGE).elc

test: $(PACKAGE).elc
	@if [ -f tests/$(PACKAGE)-tests.el ]; then \
		$(BATCH) -l ert -l $(PACKAGE).el \
		         -l tests/$(PACKAGE)-tests.el \
		         -f ert-run-tests-batch-and-exit; \
	else \
		echo "No tests found."; \
	fi

checkdoc: $(PACKAGE).elc
	@echo "Running checkdoc on $(PACKAGE).el..."
	@$(BATCH) --eval "\
	(progn \
	  (require 'checkdoc) \
	  (let ((checkdoc-diagnostic-buffer \"*chk*\") \
	        (issues 0) (output \"\")) \
	    (checkdoc-file \"$(PACKAGE).el\") \
	    (when (get-buffer \"*chk*\") \
	      (with-current-buffer \"*chk*\" \
	        (unless (zerop (buffer-size)) \
	          (setq issues (count-lines (point-min) (point-max))) \
	          (setq output (buffer-string))))) \
	    (when (get-buffer \"*Warnings*\") \
	      (with-current-buffer \"*Warnings*\" \
	        (unless (zerop (buffer-size)) \
	          (setq issues (+ issues (count-lines (point-min) (point-max)))) \
	          (setq output (concat output (buffer-string)))))) \
	    (if (> issues 0) \
	        (progn \
	          (message \"checkdoc: %d issue(s) found in $(PACKAGE).el:\" issues) \
	          (message \"%s\" output) \
	          (kill-emacs 1)) \
	      (message \"checkdoc: $(PACKAGE).el OK (no issues)\"))))"

lint: $(PACKAGE).elc
	@echo "Running package-lint checks..."
	@$(BATCH) \
	  --eval "(require 'package)" \
	  --eval "(push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives)" \
	  --eval "(package-initialize)" \
	  --eval "(condition-case err \
	            (unless (package-installed-p 'package-lint) \
	              (package-refresh-contents) \
	              (package-install 'package-lint)) \
	            (error \
	              (message \"ERROR: Failed to install package-lint: %s\" (error-message-string err)) \
	              (message \"Hint: check your network connection and MELPA availability.\") \
	              (kill-emacs 1)))" \
	  --eval "(require 'package-lint)" \
	  -f package-lint-batch-and-exit $(PACKAGE).el
	@echo "✓ package-lint passed"


ci: clean compile checkdoc lint test
	@echo ""
	@echo "✓ All CI checks passed!"
	@echo "  - Byte compilation: OK"
	@echo "  - Documentation (checkdoc): OK"
	@echo "  - Lint (package-lint): OK"
	@echo "  - Tests: $(TEST_COUNT)/$(TEST_COUNT) passing"
	@echo ""
	@echo "Package $(PACKAGE) v$(VERSION) - ready for release"

clean:
	@echo "Cleaning generated files..."
	@rm -f *.elc *~
	@echo "✓ Clean complete"
