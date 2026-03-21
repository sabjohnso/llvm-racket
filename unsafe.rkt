#lang racket/base

;; llvm/unsafe — Thin FFI layer mapping directly to the LLVM C API.
;;
;; All bindings here are unsafe foreign function calls. Misuse (wrong types,
;; use-after-free, etc.) can crash the process.

(require "private/ffi/lib.rkt"
         "private/ffi/types.rkt"
         "private/ffi/enums.rkt"
         "private/ffi/core.rkt"
         "private/ffi/analysis.rkt"
         "private/ffi/target.rkt"
         "private/ffi/target-machine.rkt"
         "private/ffi/execution-engine.rkt")

(provide (all-from-out "private/ffi/lib.rkt")
         (all-from-out "private/ffi/types.rkt")
         (all-from-out "private/ffi/enums.rkt")
         (all-from-out "private/ffi/core.rkt")
         (all-from-out "private/ffi/analysis.rkt")
         (all-from-out "private/ffi/target.rkt")
         (all-from-out "private/ffi/target-machine.rkt")
         (all-from-out "private/ffi/execution-engine.rkt"))
