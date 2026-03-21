#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide LLVM-Module-Create-With-Name-In-Context
         LLVM-Dispose-Module
         cancel-module-ownership!)

;; Ownership can transfer to an execution engine.  When it does, call
;; cancel-module-ownership! to cancel the GC finalizer.

(define-llvm LLVM-Dispose-Module
  (_fun _LLVM-Module-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Module-Create-With-Name-In-Context
  (_fun _string _LLVM-Context-Ref -> _LLVM-Module-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Module 1))

(define cancel-module-ownership!
  ((deallocator) (lambda (_mod) (void))))
