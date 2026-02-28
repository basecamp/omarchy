;;; init.el --- Omarchy Emacs configuration -*- lexical-binding: t -*-

(require 'subr-x)

;; Ensure Omarchy bin is on PATH (needed when started via emacs.service)
(let ((omarchy-bin (expand-file-name "~/.local/share/omarchy/bin")))
  (unless (member omarchy-bin exec-path)
    (add-to-list 'exec-path omarchy-bin)
    (setenv "PATH" (concat omarchy-bin ":" (getenv "PATH")))))

;;; --- Omarchy theme integration ---

(add-to-list 'load-path "~/.config/omarchy/current/theme")
(add-to-list 'custom-theme-load-path "~/.config/emacs/themes")

(defun omarchy-light-theme-p ()
  "Return non-nil if the current Omarchy theme is a light theme."
  (file-exists-p "~/.config/omarchy/current/theme/light.mode"))

(defun omarchy-apply-theme ()
  "Load Omarchy colors and apply them as an Emacs theme."
  (interactive)
  (if (load "omarchy-colors" t t)
      (progn
        (mapc #'disable-theme '(omarchy-dark omarchy-light))
        (if (omarchy-light-theme-p)
            (load-theme 'omarchy-light t)
          (load-theme 'omarchy-dark t)))
    (message "Omarchy colors not available; skipping theme load.")))

;;; --- Omarchy font integration ---

(defun omarchy-current-font ()
  "Return the current Omarchy font name."
  (string-trim
   (shell-command-to-string "omarchy-font-current")))

(defun omarchy-current-font-size ()
  "Return the current Omarchy font size in Emacs height units (1/10 pt).
The pgtk build handles display scaling natively, so no adjustment is needed.
For X11 builds running under XWayland, scale by the monitor factor."
  (let ((size (string-trim
               (shell-command-to-string
                "grep -m1 '^font.size\\|^font_size\\|^font-size' ~/.config/ghostty/config ~/.config/kitty/kitty.conf ~/.config/alacritty/alacritty.toml 2>/dev/null | grep -oP '[0-9]+\\.?[0-9]*' | head -1")))
        (scale (if (featurep 'pgtk)
                   1.0
                 (let ((s (string-to-number
                           (string-trim
                            (shell-command-to-string
                             "hyprctl monitors | grep -oP 'scale:\\s*\\K[0-9]+\\.?[0-9]*' | head -1")))))
                   (if (or (zerop s) (< s 1)) 1.0 s)))))
    (if (and size (not (string-empty-p size)))
        (truncate (* (string-to-number size) scale 10))
      120)))

(defun omarchy-apply-font ()
  "Set the Emacs default font to match Omarchy."
  (interactive)
  (let ((font (omarchy-current-font))
        (height (omarchy-current-font-size)))
    (when (and font (not (string-empty-p font)))
      (set-face-attribute 'default nil :family font :height height))))

;;; --- Clean UI ---

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(set-frame-parameter nil 'internal-border-width 8)
(add-to-list 'default-frame-alist '(internal-border-width . 8))

;; Apply on startup
(omarchy-apply-theme)
(omarchy-apply-font)

;; Start the Emacs server so theme/font changes can signal a running Emacs
(require 'server)
(unless (server-running-p)
  (server-start))

;;; --- Shell configuration ---

(setq explicit-shell-file-name "/bin/bash")
(setq explicit-bash-args
      `("--noediting" "--rcfile"
        ,(expand-file-name "shell-bashrc" user-emacs-directory) "-i"))
(setq shell-command-switch "-lc")
(setq comint-terminfo-terminal "xterm-256color")

(add-hook 'shell-mode-hook
          (lambda ()
            (add-hook 'comint-preoutput-filter-functions
                      (lambda (text)
                        (replace-regexp-in-string "\033\\][0-9]+;[^\007\033]*[\007\033\\\\]" "" text))
                      nil t)))

;;; --- Strip trailing whitespace on save ---

(add-hook 'before-save-hook #'delete-trailing-whitespace)

;;; init.el ends here
