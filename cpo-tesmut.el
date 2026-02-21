;;; cpo-tesmut.el --- Testing for buffer mutation commands -*- lexical-binding: t; -*-

(require 'ert)

(defun cpo-tesmut--parse-buffer-with-markers (text &optional point-marker mark-marker)
  "Parse TEXT with position markers, return positions and clean text.
Returns (clean-text point-pos mark-pos original-lines).
Positions are 0-based for the clean text."
  (let* ((p-marker (or point-marker "<p>"))
         (m-marker (or mark-marker "<m>"))
         (marker-specs (list (cons p-marker 'point)
                             (cons m-marker 'mark)))
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
          (gethash 'point positions)
          (gethash 'mark positions)
          original-lines)))

(defun cpo-tesmut--buffer-to-string-with-markers (point-marker mark-marker)
  "Convert current buffer to string with position markers.
Insert POINT-MARKER at point and MARK-MARKER at mark (if active)."
  (let ((text (buffer-string))
        (point-pos (1- (point)))
        (mark-pos (when (and (mark t) mark-active) (1- (mark t)))))

    ;; Insert markers from end to start to avoid position shifts
    (when (and mark-pos (>= mark-pos 0))
      (setq text (concat (substring text 0 mark-pos)
                         mark-marker
                         (substring text mark-pos))))

    ;; Adjust point position if mark was inserted before it
    (when (and mark-pos (< mark-pos point-pos))
      (setq point-pos (+ point-pos (length mark-marker))))

    (when (>= point-pos 0)
      (setq text (concat (substring text 0 point-pos)
                         point-marker
                         (substring text point-pos))))

    text))


(defmacro cpo-tesmut-test (name &rest args)
  "Test buffer mutation function with before/after text comparison or sequence testing.

NAME: test name for ert

For single function tests, provide:
  :before STRING - initial buffer text with position markers
  :after STRING - expected buffer text after function execution
  :function FUNC - function to test

For sequence tests, provide:
  :buffer-states LIST - list of buffer states (first is initial, rest are expected after each function)
  :functions LIST - list of functions to test in sequence

Common optional arguments:
  :setup FORM - setup code to run before function(s)
  :expected-result RESULT - :passed or :failed (passed through to ert)
  :transient-mark-mode BOOL - enable transient-mark-mode for test (default t)
  :point-marker STRING - marker for point position (default \"<p>\")
  :mark-marker STRING - marker for mark position (default \"<m>\")"
  (let ((before-text nil)
        (after-text nil)
        (function nil)
        (buffer-states nil)
        (functions nil)
        (setup nil)
        (expected-result :passed)
        (transient-mark-mode-setting t)
        (point-marker "<p>")
        (mark-marker "<m>")
        (remaining-args args))

    ;; Check if using old positional syntax (before after function ...)
    (if (and (>= (length args) 3) (not (keywordp (car args))))
        ;; Old syntax: (name before-text after-text function &rest keyword-args)
        (progn
          (setq before-text (nth 0 args))
          (setq after-text (nth 1 args))
          (setq function (nth 2 args))
          (setq remaining-args (nthcdr 3 args)))
      ;; New keyword syntax
      (setq remaining-args args))

    ;; Parse remaining keyword arguments
    (while remaining-args
      (pcase (pop remaining-args)
        (:before (setq before-text (pop remaining-args)))
        (:after (setq after-text (pop remaining-args)))
        (:function (setq function (pop remaining-args)))
        (:buffer-states (setq buffer-states (pop remaining-args)))
        (:functions (setq functions (pop remaining-args)))
        (:setup (setq setup (pop remaining-args)))
        (:expected-result (setq expected-result (pop remaining-args)))
        (:transient-mark-mode (setq transient-mark-mode-setting (pop remaining-args)))
        (:point-marker (setq point-marker (pop remaining-args)))
        (:mark-marker (setq mark-marker (pop remaining-args)))
        (other (error "Unknown argument: %s" other))))

    ;; Determine if this is a single test or sequence test
    (cond
     ;; Single function test
     ((and before-text after-text function)
      `(ert-deftest ,name ()
         :expected-result ,expected-result
         (let* ((before-parse-result (cpo-tesmut--parse-buffer-with-markers
                                      ,before-text ,point-marker ,mark-marker))
                (before-clean-text (nth 0 before-parse-result))
                (before-point-pos (nth 1 before-parse-result))
                (before-mark-pos (nth 2 before-parse-result))
                (after-parse-result (cpo-tesmut--parse-buffer-with-markers
                                     ,after-text ,point-marker ,mark-marker))
                (after-clean-text (nth 0 after-parse-result))
                (after-point-pos (nth 1 after-parse-result))
                (after-mark-pos (nth 2 after-parse-result)))

           (let ((old-transient-mark-mode transient-mark-mode))
             (setq transient-mark-mode ,transient-mark-mode-setting)
             (unwind-protect
                 (with-temp-buffer
                   ;; Insert clean before text
                   (insert before-clean-text)

                   ;; Set up initial positions (convert to 1-based buffer positions)
                   (when before-point-pos
                     (goto-char (1+ before-point-pos)))

                   ;; Set up mark only if mark marker was present
                   (if before-mark-pos
                       (progn
                         (set-mark (1+ before-mark-pos))
                         (activate-mark))
                     ;; Ensure mark is not active if no mark marker
                     (deactivate-mark))

                   ;; Run setup code if provided
                   ,@(when setup (list setup))

                   ;; Execute the function
                   (if (and (symbolp ,function) (commandp ,function))
                       ;; It's a symbol that is a command, call interactively
                       (call-interactively ,function)
                     ;; It's a function object, call it directly
                     (funcall ,function))

                   ;; Get actual result
                   (let ((actual-result (cpo-tesmut--buffer-to-string-with-markers ,point-marker ,mark-marker)))

                     ;; Compare with expected result
                     (unless (string= actual-result ,after-text)
                       (ert-fail (format "%s: Actual: %s, Expected: %s"
                                         ,(symbol-name name)
                                         actual-result
                                         ,after-text)))))
               ;; Restore transient-mark-mode
               (setq transient-mark-mode old-transient-mark-mode))))))

     ;; Sequence test
     ((and buffer-states functions)
      `(ert-deftest ,name ()
         :expected-result ,expected-result
         (let ((old-transient-mark-mode transient-mark-mode))
           (setq transient-mark-mode ,transient-mark-mode-setting)
           (unwind-protect
               (with-temp-buffer
                 (let* ((states ,buffer-states)
                        (funcs ,functions)
                        (initial-state (car states))
                        (expected-states (cdr states)))

                   (unless (= (length expected-states) (length funcs))
                     (error "Number of expected states must equal number of functions"))

                   ;; Parse initial state and set up buffer
                   (let* ((initial-parse-result (cpo-tesmut--parse-buffer-with-markers
                                                 initial-state ,point-marker ,mark-marker))
                          (initial-clean-text (nth 0 initial-parse-result))
                          (initial-point-pos (nth 1 initial-parse-result))
                          (initial-mark-pos (nth 2 initial-parse-result)))

                     ;; Insert clean initial text
                     (insert initial-clean-text)

                     ;; Set up initial positions
                     (when initial-point-pos
                       (goto-char (1+ initial-point-pos)))

                     (if initial-mark-pos
                         (progn
                           (set-mark (1+ initial-mark-pos))
                           (activate-mark))
                       (deactivate-mark))

                     ;; Run setup code if provided
                     ,@(when setup (list setup))

                     ;; Execute functions and check states
                     (let ((func-index 0))
                       (dolist (func funcs)
                         (let ((expected-state (nth func-index expected-states)))

                           ;; Execute the function
                           (if (and (symbolp func) (commandp func))
                               (call-interactively func)
                             (funcall func))

                           ;; Get actual result and compare
                           (let ((actual-result (cpo-tesmut--buffer-to-string-with-markers ,point-marker ,mark-marker)))
                             (unless (string= actual-result expected-state)
                               (ert-fail (format "%s (step %d): Actual: %s, Expected: %s"
                                                 ,(symbol-name name)
                                                 (1+ func-index)
                                                 actual-result
                                                 expected-state))))

                           (setq func-index (1+ func-index))))))))
             ;; Restore transient-mark-mode
             (setq transient-mark-mode old-transient-mark-mode)))))

     ;; Invalid arguments
     (t (error "Invalid arguments: must provide either (:before :after :function) or (:buffer-states :functions)")))))

(provide 'cpo-tesmut)
