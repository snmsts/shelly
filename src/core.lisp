#|
  This file is a part of shelly project.
  Copyright (c) 2012 Eitarow Fukamachi (e.arrows@gmail.com)
|#

(in-package :cl-user)
(defpackage shelly.core
  (:use :cl)
  (:shadow :read :print)
  (:import-from :swank-backend
                :quit-lisp
                :arglist)
  (:import-from :cl-fad
                :file-exists-p)
  (:import-from :shelly.impl
                :condition-undefined-function-name))
(in-package :shelly.core)

(cl-annot:enable-annot-syntax)

@export
(defun shelly.core::read (expr)
  (destructuring-bind (fn &rest args) expr
    (cons (handler-case (if (stringp fn)
                            (read-from-string fn)
                            fn)
            (error (c) (format t "Read-time error: ~A~%~A"
                               expr c)))
          (mapcar #'canonicalize-arg
                  args))))

(defun shelly.core::print (result)
  (typecase result
    (string (princ result))
    (T (pprint result))))

@export
(defun interpret (expr &key verbose)
  (when verbose
    (format *debug-io* "~&;-> ~S~%" expr))
  (let ((expr (shelly.core::read expr))
        (system-threads #+thread-support (bt:all-threads)
                        #-thread-support nil))
    (labels ((alive-user-threads ()
               (remove-if-not #'bt:thread-alive-p
                              (set-difference
                               #+thread-support (bt:all-threads)
                               #-thread-support nil
                               system-threads)))
             (wait-user-threads ()
               (loop while (alive-user-threads)
                     do (sleep 1))))
      (when verbose
        (format *debug-io* "~&;-> ~S~%" expr))

      (let ((result
             (multiple-value-list
              (handler-case (eval expr)
                (program-error ()
                  (print-usage (car expr))
                  (values))
                (undefined-function (c)
                  (let ((funcname (condition-undefined-function-name c)))
                    (if (string-equal funcname (car expr))
                        (format *error-output* "[error] command not found: ~(~S~)"
                                funcname)
                        (format *error-output* "[error] ~A" c)))
                  (values))
                (error (c)
                  (format *error-output* "[error] ~A" c)
                  (values))))))
        (when result
          (shelly.core::print (car result))))

      (fresh-line)

      (handler-case (wait-user-threads)
        (condition () nil)))))

(defun prompt ()
  (fresh-line)
  (princ "> ")
  (force-output))

@export
(defun run-repl (&key verbose)
  "Start Read-Eval-Print Loop for interactive execution."
  (prompt)
  (loop for expr = (read-line *terminal-io* nil :eof)
        until (eq expr :eof)
        do (unwind-protect
               (unless (string= "" expr)
                 (interpret
                  (mapcar #'prin1-to-string
                          (read-from-string (concatenate 'string "(" expr ")")))
                  :verbose verbose))
             (run-repl))
           (prompt)
        finally (quit-lisp)))

(defun canonicalize-arg (arg0)
  (unless (stringp arg0)
    (return-from canonicalize-arg arg0))

  (let ((arg (handler-case (progn
                             (in-package :cl-user)
                             (unwind-protect (read-from-string arg0)
                               (in-package :shelly.core)))
                (error () arg0))))
    (cond
      ((or (numberp arg) (consp arg) (typep arg 'boolean))
       arg)
      ((string= "" arg) arg)
      ((string= "--" (handler-case (subseq (string arg) 0 2)
                       (simple-error ())))
       (intern (subseq (string arg) 2)
               :keyword))
      ((ignore-errors (fad:file-exists-p arg0)))
      ((and (not (keywordp arg))
            (symbolp arg)
            (string= (package-name (symbol-package arg)) :common-lisp-user))
       (string arg0))
      (t arg))))

(defun print-usage (fn)
  (if (symbolp fn)
      (format t
              "~&Usage: ~(~A~) [~{~(~A~^ ~)~}]~%"
              fn
              (swank-backend:arglist fn))
      (format *error-output*
              "~&[error] Invalid command: ~S~%" fn)))
