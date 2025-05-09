;;; go-mod-mode.el --- Some conveniences when working with Go modules. -*- lexical-binding: t; -*-

;; Copyright (C) 2024, Adrien Brochard

;; Version: 1.0
;; Author: Adrien Brochard
;; URL: http://github.com/abrochard/go-org-mode
;; License: GNU General Public License >= 3
;; Package-Requires: ((transient "0.8.1") (flycheck "34.1") (go-mode "1.6.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; `go-mod-mode' adds support for working with go.mod files.  This
;; includes standard syntax highlighting for go.mod and go.sum files
;; as well as functions for managing a Go module project such as
;; upgrading a module, tidying up the imports, replace a module, etc.

;; This is a fork of https://github.com/zkry/go-mod-mode

;;; Code:

(require 'transient)
(require 'flycheck)
(require 'go-mode)

(defconst go-mod--source-regexp
  "\\<[a-z]+\\(?:\\.[a-z]+\\)+\\(/\\(?:[[:alnum:]-_]+/\\)*[[:alnum:]-_]+\\(?:\\.[[:alnum:]-_]+\\)?\\(?:\\.v[0-9][0-9]?\\)?\\)?"
  "Regexp for finding source names such as github.com/lib/pq.")

(defconst go-mod--version-regexp
  "\\<v[0-9]\\.[0-9]+\\.[0-9]+\\(?:-0.[0-9a-f]+\\)?\\(?:-[0-9a-f]+\\)*\\(?:+incompatible\\)?\\(?:/go.mod\\)?\\>"
  "Regexp for finding version strings.")

;;; initialize the go mod mode hook.
(defvar go-mod-mode-hook nil)
(defvar go-mod-sum-mode-hook nil)

;; use transient instead of keymap
(defvar go-mod-mode-map
  (let ((map (make-sparse-keymap)))
	(define-key map "\C-c\C-o" 'go-mod-menu)
	map)
  "The keymap used when `go-mod-minor-mode' or `go-mod-mode' is active.")

;;; go mod font lock keywords
(defconst go-mod-font-lock-keywords-1
  (list
   '("\\<\\(\\(?:modul\\|re\\(?:plac\\|quir\\)\\)e\\)\\>" . font-lock-builtin-face)
   '("\\<go 1\\.[1-9][0-9]\\>" . font-lock-builtin-face)
   `((,@go-mod--version-regexp) . font-lock-constant-face)
   `((,@go-mod--source-regexp) . font-lock-string-face)))

(defconst go-mod-sum-font-lock-keywords-1
  (list
   `((,@go-mod--version-regexp) . font-lock-constant-face)
   `((,@go-mod--source-regexp) . font-lock-string-face)))

(makunbound 'go-mod-sum-font-lock-keywords)
(defvar go-mod-font-lock-keywords go-mod-font-lock-keywords-1
  "Default highlighting expressions for go mod mode.")

(defvar go-mod-sum-font-lock-keywords go-mod-sum-font-lock-keywords-1
  "Default highlighting expressions for go mod mode.")

;;; go mod indentation rules
(defun go-mod-indent-line ()
  "Indent current line as go.mod file."
  (interactive)
  (beginning-of-line)
  (if (bobp)
	  (indent-line-to 0)
	(let ((not-indented t)
		  cur-indent)
	  (if (looking-at "^[ \t]*)")
		  (progn
			(save-excursion
			  (forward-line -1)
			  (setq cur-indent (- (current-indentation) tab-width))
			  (if (< cur-indent 0)
                  (setq cur-indent 0))))
		(save-excursion
          (while not-indented
            (forward-line -1)
            (if (looking-at "^[ \t]*)") ; Check for rule 3
                (progn
                  (setq cur-indent (current-indentation))
                  (setq not-indented nil))
										; Check for rule 4
			  (if (looking-at "^require (")
                  (progn
                    (setq cur-indent (+ (current-indentation) tab-width))
                    (setq not-indented nil))
                (if (bobp) ; Check for rule 5
                    (setq not-indented nil)))))))
	  (if cur-indent
          (indent-line-to cur-indent)
        (indent-line-to 0)))))

;;; go mod syntax table
(defvar go-mod-mode-syntax-table
  (let ((st (make-syntax-table)))
	(modify-syntax-entry ?/ ". 124b" st)
	(modify-syntax-entry ?\n "> b" st)
	st)
  "Syntax table for go-mod-mode.")

;;; go mod entry point
;;;###autoload
(defun go-mod-mode ()
  "Major mode for editing go mod files."
  (interactive)
  (when (not (executable-find "go"))
	(error "Could not find go tool.  Please see https://golang.org/doc/install to install Go"))

  (kill-all-local-variables)
  (set-syntax-table go-mod-mode-syntax-table)
  (set (make-local-variable 'font-lock-defaults) '(go-mod-font-lock-keywords))
  (set (make-local-variable 'indent-line-function) 'go-mod-indent-line)

  ;; Set comment syntax
  (set (make-local-variable 'comment-start) "//")
  (set (make-local-variable 'comment-end) "")

  ;; If GO111MODULE is off or auto, turn on.
  (when (equal "off" (getenv "GO111MODULE"))
	(setenv "GO111MODULE" "on"))
  ;; If GO111MODULE is auto and go version is 1.12, turn on.
  (when (and (equal "auto" (getenv "GO111MODULE"))
			 (string-match "go1.12" (shell-command-to-string "go version")))
	(setenv "GO111MODULE" "on"))

  (setq major-mode 'go-mod-mode)
  (add-hook 'after-save-hook 'go-mod-format t t)
  (use-local-map go-mod-mode-map)
  (run-hooks 'go-mod-mode-hook))

(defun go-mod-sum-mode ()
  "Major mode for viewing go sum files."
  (interactive)
  (kill-all-local-variables)
  (set-syntax-table (make-syntax-table))
  (set (make-local-variable 'font-lock-defaults) '(go-mod-sum-font-lock-keywords))
  (setq major-mode 'go-mod-sum-mode)
  (use-local-map go-mod-mode-map)
  (run-hooks 'go-mod-sum-mode-hook))

(define-minor-mode go-mod-minor-mode
  "Minor mode to add commadns to work with Go modules.

\\{go-mod-mode-map}"
  :init-value nil
  :keymap go-mod-mode-map
  :lighter nil)


;;; flycheck syntax checker
(flycheck-define-checker go-mod
  "A syntax checker for go.mod files."
  :command ("go" "list" "-m")
  :error-patterns
  ((error line-start (file-name) ":" line ":" column ": " (message) line-end))
  :modes go-mod-mode)

;;;###autoload
(defun flycheck-go-mod-setup ()
  "Setup Go-mod support for Flycheck.
Add `golangci-lint' to `flycheck-checkers'."
  (interactive)
  (add-hook 'flycheck-checkers 'go-mod))


;;; data extraction code
(defun go-mod--get-curent-module ()
  "Return the current module string."
  (string-trim (shell-command-to-string "go list -m")))

(defun go-mod--get-modules ()
  "Get all current modules in a list."
  (when (not (go-mod--mod-enabled)) (error "Go modules not turned on"))
  (ignore-errors
	(mapcar 'split-string (process-lines "go" "list" "-m" "all"))))

(defun go-mod--prompt-all-modules ()
  "Prompt the user to select from list of all modules."
  (completing-read "Select module: " (go-mod--get-modules)))

(defun go-mod--get-module-upgrade (mod-name &optional main)
  "Return the version that MOD-NAME can upgrade to."
  (when (not (go-mod--mod-enabled)) (error "Go modules not turned on"))
  (if main
      "main"
    (let* ((command (format "go list -m -u %s" (shell-quote-argument mod-name)))
		   (output (shell-command-to-string command)))
	  (and (string-match "\\[\\(.*\\)\\]" output)
		   (match-string 1 output)))))

(defun go-mod--get-module-versions (mod-name)
  "Return a list of the versions for a particular MOD-NAME."
  (cdr (split-string (string-trim (shell-command-to-string (format "go list -m -versions %s" (shell-quote-argument mod-name)))) nil t)))

(defun go-mod--module-on-line ()
  "Return the module string that the pointer is on."
  (if (not (or (equal "go.mod" (file-name-nondirectory (buffer-file-name (current-buffer))))
			   (equal "go.sum" (file-name-nondirectory (buffer-file-name (current-buffer))))))
	  nil
	(let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
	  (if (not (string-match go-mod--source-regexp line))
		  nil
		(progn
		  (string-match go-mod--source-regexp line)
		  (match-string 0 line))))))


(defun go-mod--mod-enabled ()
  "Return if go-mod is supported."
  (and (equal "on" (getenv "GO111MODULE"))
	   (not (equal "command-line-arguments\n" (shell-command-to-string "go list -m")))))

;;; interactive commands
(defun go-mod-upgrade (&optional main)
  "Upgrade the selected module."
  (interactive "P")
  (when (not (go-mod--mod-enabled))
	(error "Go modules not enabled"))
  (let* ((mod-name (or (go-mod--module-on-line) (go-mod--prompt-all-modules)))
		 (command (and mod-name (format "go get %s@%s" (shell-quote-argument mod-name) (if main "main" "latest"))))
		 (upgrade-to (go-mod--get-module-upgrade mod-name main)))
	(if (not upgrade-to)
		(message "Module is already at latest version")
	  (when (y-or-n-p (format "Do you want to upgrade %s to %s? " mod-name upgrade-to))
		(message "Please wait while module is being updated.")
		(message (shell-command-to-string command))))))

(defun go-mod-upgrade-all (arg)
  "Upgrade all modules in go.mod.

You can modify this command with a prefix ARG by pressing \\[universal-argument]
which will only patch-upgrade available modules."
  (interactive "P")
  (if (= arg 4)
	  (compilation-start "go get -u=patch -m all")
	(compilation-start "go get -u -m all")))

(defun go-mod-get ()
  "List all of the available versions of module and select version to set it at."
  (interactive)
  (when (not (go-mod--mod-enabled))
	(error "Go modules not enabled"))

  (let* ((mod-name (or (go-mod--module-on-line) (go-mod--prompt-all-modules)))
		 (versions (go-mod--get-module-versions mod-name)))
	;; fail if no versions for the module are available
	(if (= 0 (length versions))
		(message (format "Module %s has no other available versions." mod-name))
	  (let* ((selected-version (completing-read "Select version: " versions))
			 (command (format "go get %s@%s" mod-name (shell-quote-argument selected-version))))
		(message (shell-command-to-string command))))))

(defun go-mod-tidy ()
  "Run go mod tidy."
  (interactive)
  (shell-command "go mod tidy"))

(defun go-mod-replace ()
  "Replace a go module with one on disk."
  (interactive)
  (let ((mod-name (or (go-mod--module-on-line) (go-mod--prompt-all-modules)))
        (dir (file-relative-name (read-file-name "Local version: "))))
    (shell-command (format "go mod edit -replace %s=%s" mod-name dir))))

(defun go-mod-why ()
  "Print go mod why for module."
  (interactive)
  (shell-command (format "go mod why %s"
                         (or (go-mod--module-on-line) (go-mod--prompt-all-modules)))))

(defun go-mod-format ()
  "Use go mod edit -fmt to format go.mod."
  (interactive)
  (shell-command "go mod edit -fmt"))

(add-to-list 'auto-mode-alist '("go\\.mod\\'" . go-mod-mode))
(add-to-list 'auto-mode-alist '("go\\.sum\\'" . go-mod-sum-mode))

(transient-define-prefix go-mod-menu ()
  ["Actions"
   ("t" "tidy" go-mod-tidy)
   ("u" "upgrade package" go-mod-upgrade)
   ("U" "upgrade all packages" go-mod-upgrade-all)
   ("i" "import package" go-import-add)
   ("g" "get version" go-mod-get)
   ("r" "replace" go-mod-replace)
   ("w" "why" go-mod-why)])

(provide 'go-mod-mode)

;;; go-mod-mode.el ends here
