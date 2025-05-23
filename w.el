;;; w.el --- Simple live serving system for static files -*- lexical-binding: t; -*-

;; Copyright (c) 2018-2024 Abhinav Tushar

;; Author: Abhinav Tushar <lepisma@fastmail.com>
;; Version: 0.0.9
;; Package-Requires: ((emacs "25"))
;; URL: https://github.com/lepisma/w.el

;;; Commentary:

;; Simple live serving system for static files
;; This file is not a part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'cl-seq)
(require 'eieio)

(defgroup w nil
  "w server launcher")

(defcustom w-start-port 8080
  "First port to check for"
  :type 'natnum
  :group 'w)

(defcustom w-launchers '(("live-server" . w-launcher-default))
  "Launcher functions and identifiers"
  :group 'w)

(defun w-launcher-default (dir port)
  "Default launcher using live-server"
  (let ((default-directory (expand-file-name dir)))
    (start-process "live-server" nil "live-server" "--host=127.0.0.1" (format "--port=%s" port) "--index")))

(defvar w-instances '()
  "List of instances currently active")

(defun w-port-active-p (port)
  "Check if a port is getting used"
  (let ((cmd (format "ss -tl4 '( sport = :%s )' | grep LISTEN"
                     (number-to-string port))))
    (> (length (shell-command-to-string cmd)) 0)))

(defun w-get-free-port (&optional start)
  "Return a free port"
  (let ((port (or start w-start-port)))
    (if (w-port-active-p port)
        (w-get-free-port (+ 1 port))
      port)))

(defclass w ()
  ((dir :initarg :dir
        :documentation "Directory for the process")
   (port :initarg :port
         :documentation "Port the server is running on")
   (launcher :initarg :launcher
             :documentation "Identifier for the launcher")
   (process :initarg :process
            :initform nil
            :documentation "Holder for the running process"))
  "A single process with info")

(cl-defmethod w-kill ((wi w))
  "Kill the connected process"
  (let ((process (oref wi process)))
    (if (process-live-p process)
        (progn
          (kill-process process)
          (setq w-instances (delete wi w-instances))))))

(cl-defmethod w-browse ((wi w) &optional rel-path)
  "Run browser for the process. REL-PATH starts with a `/' char."
  (browse-url (format "http://localhost:%s%s" (oref wi port) (or rel-path ""))))

(cl-defmethod w-pp ((wi w))
  "Pretty print process"
  (format "[%s] %s: %s" (oref wi port) (oref wi launcher) (abbreviate-file-name (oref wi dir))))

(defun w-dir-live-p (dir)
  "Tell which instance is serving DIR"
  (cl-find dir w-instances :key (lambda (wi) (oref wi :dir))))

(defun w-create (dir launcher)
  (let* ((port (w-get-free-port))
         (process (funcall (cdr launcher) dir port))
         (wi (w :dir dir
                :port port
                :launcher (car launcher)
                :process process)))
    (setq w-instances (cons wi w-instances))
    wi))

(defun w--complete-and-act (prompt collection action-fn)
  (let ((completion-match (completing-read prompt collection)))
    (funcall action-fn (alist-get completion-match collection nil nil #'string-equal))))

;;;###autoload
(defun w-start-here (&optional rel-path)
  (interactive)
  (w-start default-directory rel-path))

;;;###autoload
(defun w-start (&optional dir rel-path)
  "Start a new w instance in DIR"
  (interactive "DRoot directory: ")
  (let ((wi (w-dir-live-p dir)))
    (if wi (w-browse wi rel-path)
      (let* ((n-launchers (length w-launchers)))
        (cond ((= n-launchers 0) (signal 'error "No launcher found"))
              ((= n-launchers 1) (w-browse (w-create dir (car w-launchers)) rel-path))
              (t (w--complete-and-act "Available launchers: "
                                      (mapcar (lambda (l) (cons (car l) l)) w-launchers)
                                      (lambda (l) (w-browse (w-create dir l) rel-path)))))))))

(defun w-open-browser (&optional rel-path)
  "Start browser for a w instance"
  (interactive)
  (let ((n-instances (length w-instances)))
    (cond ((= n-instances 0) (message "No w instances running"))
          ((= n-instances 1) (w-browse (car w-instances) rel-path))
          (t (w--complete-and-act "Running w instances"
                                  (mapcar (lambda (wi) (cons (w-pp wi) wi)) w-instances)
                                  (lambda (wi) (w-browse wi rel-path)))))))

(defun w-stop ()
  "Stop a w instance"
  (interactive)
  (let ((n-instances (length w-instances)))
    (cond ((= n-instances 0) (message "No w instances running"))
          ((= n-instances 1) (w-kill (car w-instances)))
          (t (w--complete-and-act "Running w instances"
                                  (mapcar (lambda (wi) (cons (w-pp wi) wi)) w-instances)
                                  'w-kill)))))

(provide 'w)

;;; w.el ends here
