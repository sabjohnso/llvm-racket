#lang racket/base

;; llvm — Safe, high-level LLVM interface for Racket.
;;
;; Re-exports the safe API so users can write:
;;   (require llvm)
;; For the thin/unsafe FFI layer, use:
;;   (require llvm/unsafe)

(require "safe.rkt")
(provide (all-from-out "safe.rkt"))
