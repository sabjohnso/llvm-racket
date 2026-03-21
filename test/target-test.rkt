#lang racket/base

(module+ test
  (require rackunit
           llvm/private/ffi/target)

  (test-case "initialize native target without crash"
    (check-not-exn Initialize-Native-Target!)))
