;;; carettest-tesprop.el --- Testing for property-style buffer assertions -*- lexical-binding: t; -*-

(require 'carettest-tesmut)

(defun carettest--tesprop-count-marker-occurrences (text marker)
  "Return the number of times MARKER appears in TEXT."
  (when (= (length marker) 0)
    (error "carettest-tesprop: marker strings may not be empty"))
  (let ((count 0)
        (search-pos 0))
    (while (string-match (regexp-quote marker) text search-pos)
      (setq count (1+ count))
      (setq search-pos (match-end 0)))
    count))

(defun carettest--tesprop-validate-marker-count (text marker marker-name)
  "Signal an error if TEXT contains more than one MARKER.
MARKER-NAME is used in the error message."
  (let ((count (carettest--tesprop-count-marker-occurrences text marker)))
    (when (> count 1)
      (error "carettest-tesprop: TEXT may contain at most one %s marker (%s), found %d"
             marker-name marker count))))

(defun carettest--tesprop-parse-buffer-with-markers (text &optional point-marker mark-marker)
  "Parse TEXT with position markers and return clean text plus positions.
Returns (clean-text point-pos mark-pos original-lines).
Positions are 0-based for the clean text."
  (let ((p-marker (or point-marker "<p>"))
        (m-marker (or mark-marker "<m>")))
    (carettest--tesprop-validate-marker-count text p-marker "point")
    (carettest--tesprop-validate-marker-count text m-marker "mark")
    (carettest--tesmut-parse-buffer-with-markers text p-marker m-marker)))

(defun carettest--tesprop-parse-args (args)
  "Parse ARGS for tesprop option keywords and body forms."
  (let ((setup nil)
        (transient-mark-mode-setting t)
        (point-marker "<p>")
        (mark-marker "<m>")
        (remaining-args args))
    (while (and remaining-args (keywordp (car remaining-args)))
      (pcase (pop remaining-args)
        (:setup (setq setup (pop remaining-args)))
        (:transient-mark-mode (setq transient-mark-mode-setting (pop remaining-args)))
        (:point-marker (setq point-marker (pop remaining-args)))
        (:mark-marker (setq mark-marker (pop remaining-args)))
        (other (error "Unknown argument: %s" other))))
    (list :setup setup
          :transient-mark-mode transient-mark-mode-setting
          :point-marker point-marker
          :mark-marker mark-marker
          :body remaining-args)))

(defmacro carettest-with-tesprop-buffer (text &rest args)
  "Set up a temporary buffer for tesprop assertions around TEXT.

Recognized keywords are the same as `carettest-tesprop':
  :setup FORM
  :transient-mark-mode BOOL
  :point-marker STRING
  :mark-marker STRING

Any remaining forms are evaluated in the configured buffer."
  (let* ((parsed-args (carettest--tesprop-parse-args args))
         (setup (plist-get parsed-args :setup))
         (transient-mark-mode-setting (plist-get parsed-args :transient-mark-mode))
         (point-marker (plist-get parsed-args :point-marker))
         (mark-marker (plist-get parsed-args :mark-marker))
         (body (plist-get parsed-args :body)))
    `(let* ((parse-result (carettest--tesprop-parse-buffer-with-markers
                           ,text ,point-marker ,mark-marker))
            (clean-text (nth 0 parse-result))
            (point-pos (nth 1 parse-result))
            (mark-pos (nth 2 parse-result))
            (old-transient-mark-mode transient-mark-mode))
       (setq transient-mark-mode ,transient-mark-mode-setting)
       (unwind-protect
           (with-temp-buffer
             (insert clean-text)
             (when point-pos
               (goto-char (1+ point-pos)))
             (if mark-pos
                 (progn
                   (set-mark (1+ mark-pos))
                   (activate-mark))
               (deactivate-mark))
             ,@(when setup (list setup))
             ,@body)
         (setq transient-mark-mode old-transient-mark-mode)))))

(defmacro carettest-tesprop (name text &rest args)
  "Define an ERT test NAME that checks predicates against TEXT.

TEXT uses a single `<p>` point marker and, optionally, a single `<m>`
mark marker.  Optional keyword arguments are:
  :setup FORM
  :transient-mark-mode BOOL
  :point-marker STRING
  :mark-marker STRING

The remaining forms are treated as predicates and each is wrapped in
`should`."
  (let* ((parsed-args (carettest--tesprop-parse-args args))
         (setup (plist-get parsed-args :setup))
         (transient-mark-mode-setting (plist-get parsed-args :transient-mark-mode))
         (point-marker (plist-get parsed-args :point-marker))
         (mark-marker (plist-get parsed-args :mark-marker))
         (body (plist-get parsed-args :body)))
    `(ert-deftest ,name ()
       (carettest-with-tesprop-buffer ,text
         ,@(when setup `(:setup ,setup))
         ,@(unless (equal transient-mark-mode-setting t)
             `(:transient-mark-mode ,transient-mark-mode-setting))
         ,@(unless (string= point-marker "<p>")
             `(:point-marker ,point-marker))
         ,@(unless (string= mark-marker "<m>")
             `(:mark-marker ,mark-marker))
         ,@(mapcar (lambda (form) `(should ,form)) body)))))

(provide 'carettest-tesprop)

;;; carettest-tesprop.el ends here
