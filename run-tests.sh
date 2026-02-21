#!/bin/bash
set -euo pipefail

emacs -batch -l ert -l cpo-tesmo.el -l test-cpo-tesmo.el -f ert-run-tests-batch-and-exit
emacs -batch -l ert -l cpo-tesmut.el -l test-cpo-tesmut.el -f ert-run-tests-batch-and-exit
