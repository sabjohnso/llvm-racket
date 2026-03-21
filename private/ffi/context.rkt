#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide LLVM-Context-Create
         LLVM-Context-Dispose)

(define-llvm LLVM-Context-Dispose
  (_fun _LLVM-Context-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Context-Create
  (_fun -> _LLVM-Context-Ref)
  #:wrap (allocator LLVM-Context-Dispose))
