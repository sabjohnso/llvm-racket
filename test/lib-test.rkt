#lang racket/base

(module+ test
  (require rackunit
           llvm/private/ffi/lib)

  (test-case "libLLVM loads successfully"
    (check-not-false llvm-lib)))
