;;; cpo-tesmo.el --- Testing for movement commands -*- lexical-binding: t; -*-

(require 'ert)

(defun cpo-tesmo--parse-buffer-with-markers (text &optional point-before point-after mark-before mark-after)
  "Parse TEXT with position markers, return positions and clean text.
Returns (clean-text point-before-pos point-after-pos mark-before-pos mark-after-pos original-lines).
Positions are 0-based for the clean text."
  (let* ((p0-marker (or point-before "<p0>"))
         (p1-marker (or point-after "<p1>"))
         (m0-marker (or mark-before "<m0>"))
         (m1-marker (or mark-after "<m1>"))
         (marker-specs (list (cons p0-marker 'point-before)
                             (cons p1-marker 'point-after)
                             (cons m0-marker 'mark-before)
                             (cons m1-marker 'mark-after)))
         (original-lines (split-string text "\n"))
         (positions (make-hash-table :test 'eq))
         (found-markers '())
         (clean-text text))

    ;; First pass: find all marker positions without removing them
    (dolist (marker-spec marker-specs)
      (let ((marker (car marker-spec))
            (type (cdr marker-spec))
            (search-pos 0))
        (while (string-match (regexp-quote marker) text search-pos)
          (let ((found-pos (match-beginning 0)))
            (push (list found-pos (length marker) type) found-markers)
            (setq search-pos (match-end 0))))))

    ;; Sort markers by position (descending) so we can remove from end to start
    (setq found-markers (sort found-markers (lambda (a b) (> (car a) (car b)))))

    ;; Second pass: remove markers from end to start and record clean positions
    (dolist (marker-info found-markers)
      (let ((pos (nth 0 marker-info))
            (len (nth 1 marker-info))
            (type (nth 2 marker-info)))
        ;; Record the position in the clean text (accounting for previously removed markers)
        (puthash type pos positions)
        ;; Remove the marker
        (setq clean-text (concat (substring clean-text 0 pos)
                                 (substring clean-text (+ pos len))))))

    ;; Adjust positions to account for removed markers that came before each position
    (maphash (lambda (type pos)
               (let ((adjusted-pos pos))
                 ;; Count how many marker characters were removed before this position
                 (dolist (marker-info found-markers)
                   (let ((marker-pos (nth 0 marker-info))
                         (marker-len (nth 1 marker-info)))
                     (when (< marker-pos pos)
                       (setq adjusted-pos (- adjusted-pos marker-len)))))
                 (puthash type adjusted-pos positions)))
             positions)

    (list clean-text
          (gethash 'point-before positions)
          (gethash 'point-after positions)
          (gethash 'mark-before positions)
          (gethash 'mark-after positions)
          original-lines)))

(defun cpo-tesmo--buffer-position-to-line-col (pos text)
  "Convert buffer position POS to line and column in TEXT.
Returns (line-num col-num line-content) where line-num is 1-based."
  (let ((lines (split-string text "\n"))
        (current-pos 0)
        (line-num 1))
    (catch 'found
      (dolist (line lines)
        (let ((line-end (+ current-pos (length line))))
          (if (<= pos line-end)
              (throw 'found (list line-num (- pos current-pos) line))
            (setq current-pos (+ line-end 1)) ; +1 for newline
            (setq line-num (1+ line-num)))))
      ;; If we get here, position is beyond end of text
      (list line-num 0 ""))))

(defun cpo-tesmo--insert-marker-at-position (text pos marker)
  "Insert MARKER at position POS in TEXT, return modified text."
  (if (and pos (>= pos 0) (<= pos (length text)))
      (concat (substring text 0 pos) marker (substring text pos))
    text))

(defun cpo-tesmo--filter-markers-except (text keep-marker all-markers)
  "Remove all markers from TEXT except KEEP-MARKER.
ALL-MARKERS is the list of all possible markers to filter out."
  (let ((result text))
    (dolist (marker all-markers)
      (unless (string= marker keep-marker)
        (setq result (replace-regexp-in-string (regexp-quote marker) "" result))))
    result))

(defun cpo-tesmo--format-failure-message (test-name expected-pos actual-pos pos-type text original-lines marker all-markers)
  "Format a detailed failure message for position mismatch."
  (let* ((expected-info (when expected-pos (cpo-tesmo--buffer-position-to-line-col expected-pos text)))
         (actual-info (cpo-tesmo--buffer-position-to-line-col actual-pos text))
         (expected-line-num (when expected-info (nth 0 expected-info)))
         (actual-line-num (nth 0 actual-info))
         (actual-line-content (nth 2 actual-info))
         (actual-col (nth 1 actual-info))
         (marked-actual-line (cpo-tesmo--insert-marker-at-position actual-line-content actual-col marker))
         (original-expected-line (if (and expected-line-num (<= expected-line-num (length original-lines)))
                                     (nth (1- expected-line-num) original-lines)
                                   "N/A"))
         (filtered-expected-line (if (string= original-expected-line "N/A")
                                     "N/A"
                                   (cpo-tesmo--filter-markers-except original-expected-line marker all-markers))))

    (format "%s mismatch for %s (%s): Expected: %s (line %s, pos %s) Actual: %s (line %s, pos %s)"
            test-name
            pos-type
            marker
            filtered-expected-line
            (or expected-line-num "N/A")
            (or expected-pos "N/A")
            marked-actual-line
            (or actual-line-num "N/A")
            (or actual-pos "N/A"))))

(defmacro cpo-tesmo-test (name text movement-function &rest args)
  "Test movement function with position markers in text.
NAME: test name for ert
TEXT: buffer text with position markers
MOVEMENT-FUNCTION: function to test (can be a closure or quoted symbol)
ARGS: optional arguments:
  :setup FORM - setup code to run before movement
  :expected-result RESULT - :passed or :failed (passed through to ert)
  :transient-mark-mode BOOL - enable transient-mark-mode for test (default t)
  :points LIST - list of point markers (default '(\"<p0>\" \"<p1>\"))
  :marks LIST - list of mark markers (default '(\"<m0>\" \"<m1>\"))"
  (let ((setup nil)
        (expected-result :passed)
        (transient-mark-mode-setting t)
        (points-list '("<p0>" "<p1>"))
        (marks-list '("<m0>" "<m1>"))
        (remaining-args args))

    ;; Parse optional arguments
    (while remaining-args
      (pcase (pop remaining-args)
        (:setup (setq setup (pop remaining-args)))
        (:expected-result (setq expected-result (pop remaining-args)))
        (:transient-mark-mode (setq transient-mark-mode-setting (pop remaining-args)))
        (:points (setq points-list (pop remaining-args)))
        (:marks (setq marks-list (pop remaining-args)))
        (other (error "Unknown argument: %s" other))))

    `(ert-deftest ,name ()
       :expected-result ,expected-result
       (let* ((parse-result (cpo-tesmo--parse-buffer-with-markers
                             ,text
                             ,(car points-list)
                             ,(cadr points-list)
                             ,(car marks-list)
                             ,(cadr marks-list)))
              (clean-text (nth 0 parse-result))
              (point-before-pos (nth 1 parse-result))
              (point-after-pos (nth 2 parse-result))
              (mark-before-pos (nth 3 parse-result))
              (mark-after-pos (nth 4 parse-result))
              (original-lines (nth 5 parse-result)))

         (let ((old-transient-mark-mode transient-mark-mode))
           (setq transient-mark-mode ,transient-mark-mode-setting)
           (unwind-protect
               (with-temp-buffer
                 ;; Insert clean text
                 (insert clean-text)

                 ;; Set up initial positions (convert to 1-based buffer positions)
                 (when point-before-pos
                   (goto-char (1+ point-before-pos)))

                 ;; Set up mark only if mark-before marker was present
                 (if mark-before-pos
                     (progn
                       (set-mark (1+ mark-before-pos))
                       (activate-mark))
                   ;; Ensure mark is not active if no mark-before marker
                   (deactivate-mark))

                 ;; Run setup code if provided
                 ,@(when setup (list setup))

                 ;; Execute the movement function
                 (if (functionp ,movement-function)
                     ;; It's a closure/function object
                     (funcall ,movement-function)
                   ;; It's a symbol, call interactively
                   (call-interactively ,movement-function))

                 ;; Check results (convert back to 0-based for comparison)
                 (let ((actual-point-pos (1- (point)))
                       (actual-mark-pos (when (mark t) (1- (mark t)))))

                   ;; Check point position
                   (when point-after-pos
                     (unless (= actual-point-pos point-after-pos)
                       (ert-fail (cpo-tesmo--format-failure-message
                                  ,(symbol-name name)
                                  point-after-pos
                                  actual-point-pos
                                  "point"
                                  clean-text
                                  original-lines
                                  ,(cadr points-list)
                                  (list ,@points-list ,@marks-list)))))

                   ;; Check mark position and activity
                   (if mark-after-pos
                       ;; Expected mark position specified - mark should be active and at correct position
                       (progn
                         (unless mark-active
                           (ert-fail (format "%s: Expected mark to be active but it was not" ,(symbol-name name))))
                         (unless (and actual-mark-pos (= actual-mark-pos mark-after-pos))
                           (ert-fail (cpo-tesmo--format-failure-message
                                      ,(symbol-name name)
                                      mark-after-pos
                                      actual-mark-pos
                                      "mark"
                                      clean-text
                                      original-lines
                                      ,(cadr marks-list)
                                      (list ,@points-list ,@marks-list)))))
                     ;; No expected mark position - mark should not be active
                     (when mark-active
                       (ert-fail (format "%s: Expected mark to be inactive but it was active" ,(symbol-name name)))))))
             ;; Restore transient-mark-mode
             (setq transient-mark-mode old-transient-mark-mode)))))))

(provide 'cpo-tesmo)
