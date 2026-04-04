# carettest

Testing library for Emacs commands.

The core idea is that I wanted an easy way to test movement (and later editing) commands in emacs in a way where the test is brief and easy to verify quickly, using a syntax similar to the way people write examples of text editing online.
Other people have probably made similar things, but I didn't see anything compelling for my use case, so I made this.

- **tesmo** ("test movement"): tests that a movement command moves
  point (and optionally mark) from one position to another.
- **tesmut** ("test mutation"): tests that a buffer-editing command
  transforms a buffer from one state to another.
- **tesprop** ("test properties"): tests a buffer setup against a
  series of assertions, each wrapped in `should`.
  
## tesmo

Use `carettest-tesmo-test` to test movement commands.  Embed `<p0>`
for the starting point and `<p1>` for the expected ending point.  Use
`<m0>` and `<m1>` for mark positions.

```elisp
;; forward-word should move from before "world" to after it
(carettest-tesmo-test test-forward-word
  "hello <p0>world<p1> test"
  'forward-word)

;; Lambda for multi-step movement
(carettest-tesmo-test test-forward-word-twice
  "one <p0>two three<p1> four"
  (lambda () (forward-word 2)))

;; With mark: verify region after mark-word
(carettest-tesmo-test test-mark-word
  "hello <p0><p1><m0>word<m1> test"
  'mark-word)
```

See docstrings in the source (or in emacs help viewer) for more options.

## tesmut

Use `carettest-tesmut-test` to test buffer mutations.  Embed `<p>` for
point and `<m>` for mark in both the `:before` and `:after` strings.

```elisp
;; insert should add a character and advance point
(carettest-tesmut-test test-insert
  :before "hello <p>world"
  :after  "hello X<p>world"
  :function (lambda () (insert "X")))

;; upcase-region operates on the active region
(carettest-tesmut-test test-upcase-region
  :before "hello <p>world<m> test"
  :after  "hello <p>WORLD<m> test"
  :function 'upcase-region)

;; Multi-step sequence test
(carettest-tesmut-test test-kill-yank
  :buffer-states '("hello <p>world test"
                   "hello <p> test"
                   "hello world<p> test")
  :functions '((lambda () (kill-word 1))
               yank))
```

See docstrings in the source (or in emacs help viewer) for more options.

## tesprop

Use `carettest-tesprop` for assertion-style tests.  Embed a single
`<p>` for point and, optionally, a single `<m>` for mark, then provide
predicate forms that are wrapped in `should`.

```elisp
(carettest-tesprop test-buffer-state
  "hello <m>world<p> test"
  mark-active
  (= (point) 12)
  (= (mark) 7)
  (string= (buffer-string) "hello world test"))
```

For lower-level use inside an existing ERT test, call
`carettest-with-tesprop-buffer` and write the `should` forms yourself.

## Generators

Also there are functions to generate tests.

The generators are useful for writing tests that CAPTURE CURRENT BEHAVIOR.

My main motivation for this was to generate a bunch of tests that I wouldn't necessarily write myself, but with tesmo it is easy to see the start and end conditions together and evaluate whether a test is correct.
So I can generate a bunch of tests and see whether it all looks right, then maybe choose a few to go into a test suite, or maybe just throw them out.
It may also be useful to lock in behavior before refactoring.

The generator variants (`carettest-tesmo-generate-tests`, `carettest-tesmut-generate-tests`) run commands at random positions in sample text and write out the captured results as test cases.

See the `examples/` directory for runnable generator scripts.
