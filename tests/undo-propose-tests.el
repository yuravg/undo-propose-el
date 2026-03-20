;;; undo-propose-tests.el --- Tests for undo-propose  -*- lexical-binding: t -*-

(require 'ert)
(require 'undo-propose)

;;; Code:

;;; Helpers

(defmacro with-undoable-temp-buffer (&rest body)
  "Like `with-temp-buffer', but doesn't disable `undo'.
Executes BODY in the temporary buffer."
  `(let ((temp-buffer (generate-new-buffer
                       ;; this must NOT start with a space, otherwise
                       ;; undo won't work. See `get-buffer-create'
                       "*temp*")))
     (unwind-protect
         (with-current-buffer temp-buffer
           ,@body)
       (kill-buffer temp-buffer))))

(defmacro with-undo-propose-test (initial &rest body)
  "Set up a temp buffer with INITIAL text, open undo-propose, run BODY.
BODY runs inside the undo-propose buffer.  The original buffer is
bound to `orig-buf'."
  (declare (indent 1))
  `(with-undoable-temp-buffer
    (insert ,initial)
    (undo-boundary)
    (let ((orig-buf (current-buffer)))
      (undo-propose)
      ,@body)))

;;; commit

(ert-deftest undo-propose-commit-copies-buffer ()
  "Committing copies the proposed buffer content back to the parent."
  (with-undo-propose-test "hello"
                          (let ((inhibit-read-only t))
                            (erase-buffer)
                            (insert "world"))
                          (undo-propose-commit)
                          (should (equal (buffer-string) "world"))))

(ert-deftest undo-propose-commit-copies-undo-ring ()
  "Committing copies the undo-ring back so changes can be undone."
  (with-undo-propose-test "first"
                          (call-interactively (command-remapping 'undo))
                          (undo-propose-commit)
                          ;; after commit, parent should be undoable back to empty
                          (undo)
                          (should (equal (buffer-string) ""))))

(ert-deftest undo-propose-commit-restores-point ()
  "Committing restores point to the position in the propose buffer."
  (with-undo-propose-test "hello world"
                          (goto-char 6)
                          (undo-propose-commit)
                          (should (= (point) 6))))

(ert-deftest undo-propose-commit-kills-propose-buffer ()
  "Committing kills the temporary undo-propose buffer."
  (with-undo-propose-test "hello"
                          (let ((propose-buf (current-buffer)))
                            (undo-propose-commit)
                            (should-not (buffer-live-p propose-buf)))))

;;; squash-commit

(ert-deftest undo-propose-squash-commit-copies-buffer ()
  "Squash-committing copies buffer content to the parent."
  (with-undo-propose-test "hello"
                          (call-interactively (command-remapping 'undo))
                          (undo-propose-squash-commit)
                          (should (equal (buffer-string) ""))))

(ert-deftest undo-propose-squash-commit-does-not-copy-undo-ring ()
  "Squash-committing does NOT copy the propose buffer's undo-ring to the parent."
  (with-undo-propose-test "first"
                          (call-interactively (command-remapping 'undo))
                          ;; capture propose buffer's undo-list after undoing
                          (let ((propose-undo-list buffer-undo-list))
                            (undo-propose-squash-commit)
                            ;; parent undo-list must differ from propose buffer's undo-list
                            (with-current-buffer orig-buf
                              (should-not (equal buffer-undo-list propose-undo-list))))))

(ert-deftest undo-propose-squash-commit-noop-when-unchanged ()
  "Squash-committing without undoing leaves the parent buffer unchanged."
  (with-undo-propose-test "hello"
                          (let ((undo-list-before buffer-undo-list))
                            (undo-propose-squash-commit)
                            (should (equal (buffer-string) "hello"))
                            (should (equal buffer-undo-list undo-list-before)))))

;;; cancel

(ert-deftest undo-propose-cancel-leaves-parent-unchanged ()
  "Cancelling does not modify the parent buffer content."
  (with-undo-propose-test "original"
                          (let ((inhibit-read-only t))
                            (erase-buffer)
                            (insert "discarded"))
                          (undo-propose-cancel)
                          (with-current-buffer orig-buf
                            (should (equal (buffer-string) "original")))))

(ert-deftest undo-propose-cancel-kills-propose-buffer ()
  "Cancelling kills the temporary undo-propose buffer."
  (with-undo-propose-test "hello"
                          (let ((propose-buf (current-buffer)))
                            (undo-propose-cancel)
                            (should-not (buffer-live-p propose-buf)))))

;;; nested call

(ert-deftest undo-propose-nested-call-runs-undo ()
  "Calling undo-propose inside an undo-propose buffer runs undo instead."
  (with-undo-propose-test "hello"
                          (let ((inhibit-read-only t))
                            (insert " world")
                            (undo-boundary))
                          ;; second call should undo the " world" insertion
                          (undo-propose)
                          (should (equal (buffer-string) "hello"))
                          (undo-propose-cancel)))

;;; hooks

(ert-deftest undo-propose-entry-hook-runs-on-entry ()
  "`undo-propose-entry-hook' fires when entering the propose buffer."
  (with-undoable-temp-buffer
   (let ((fired nil))
     (add-hook 'undo-propose-entry-hook (lambda () (setq fired t)))
     (unwind-protect
         (progn
           (undo-propose)
           (should fired)
           (undo-propose-cancel))
       (remove-hook 'undo-propose-entry-hook (lambda () (setq fired t)))))))

(ert-deftest undo-propose-done-hook-runs-on-commit ()
  "`undo-propose-done-hook' fires after committing."
  (with-undo-propose-test "hello"
                          (let ((fired nil))
                            (add-hook 'undo-propose-done-hook (lambda () (setq fired t)))
                            (unwind-protect
                                (progn
                                  (undo-propose-commit)
                                  (should fired))
                              (remove-hook 'undo-propose-done-hook (lambda () (setq fired t)))))))

(ert-deftest undo-propose-done-hook-runs-on-cancel ()
  "`undo-propose-done-hook' fires even when cancelling."
  (with-undo-propose-test "hello"
                          (let ((fired nil))
                            (add-hook 'undo-propose-done-hook (lambda () (setq fired t)))
                            (unwind-protect
                                (progn
                                  (undo-propose-cancel)
                                  (should fired))
                              (remove-hook 'undo-propose-done-hook (lambda () (setq fired t)))))))

;;; read-only source (reference snapshot)

(ert-deftest undo-propose-readonly-source-sets-flag ()
  "Opening undo-propose on a buffer with no undo history sets the snapshot flag."
  (let ((buf (generate-new-buffer "*ro-test*")))
    (unwind-protect
        (with-current-buffer buf
          (setq buffer-undo-list t)
          (undo-propose)
          (should undo-propose-read-only-source)
          (undo-propose-cancel))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest undo-propose-readonly-source-allows-undo-in-propose ()
  "In snapshot mode the propose buffer has its own undo history."
  (let ((buf (generate-new-buffer "*ro-test*")))
    (unwind-protect
        (with-current-buffer buf
          (setq buffer-undo-list t)
          (undo-propose)
          (let ((inhibit-read-only t))
            (insert "typed in propose")
            (undo-boundary))
          (call-interactively (command-remapping 'undo))
          (should (equal (buffer-string) ""))
          (undo-propose-cancel))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;; org-clock marker integration (existing test, kept for regression)

(ert-deftest undo-propose-test-org-clock ()
  (with-undoable-temp-buffer
   (org-mode)
   (insert "* test\n")
   (undo-boundary)
   (org-clock-in)
   (undo-boundary)
   (goto-char (point-max))
   (insert "\nfoobar")
   (undo-boundary)
   (undo-propose)
   (call-interactively (command-remapping 'undo))
   (undo-propose-commit)
   (org-clock-out)))

(provide 'undo-propose-tests)

;;; undo-propose-tests.el ends here
