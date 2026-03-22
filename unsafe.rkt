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
         "private/ffi/execution-engine.rkt"
         "private/ffi/passes.rkt"
         "private/ffi/bitcode.rkt"
         "private/ffi/orc.rkt"
         "private/ffi/linker.rkt")

(provide (all-from-out "private/ffi/lib.rkt")
         (all-from-out "private/ffi/types.rkt")
         (all-from-out "private/ffi/enums.rkt")
         (all-from-out "private/ffi/core.rkt")
         (all-from-out "private/ffi/analysis.rkt")
         (all-from-out "private/ffi/target.rkt")
         (all-from-out "private/ffi/target-machine.rkt")
         (all-from-out "private/ffi/execution-engine.rkt")
         (all-from-out "private/ffi/passes.rkt")
         (all-from-out "private/ffi/bitcode.rkt")
         (all-from-out "private/ffi/orc.rkt")
         (all-from-out "private/ffi/linker.rkt"))
