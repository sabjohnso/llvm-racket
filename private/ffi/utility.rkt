#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide LLVM-Dispose-Message
         LLVM-Print-Module-To-String
         LLVM-Get-Buffer-Start
         LLVM-Get-Buffer-Size
         LLVM-Dispose-Memory-Buffer)

;; ---- Messages --------------------------------------------------------------

(define-llvm LLVM-Dispose-Message
  (_fun _pointer -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Print-Module-To-String
  (_fun _LLVM-Module-Ref -> _pointer)
  #:wrap (allocator LLVM-Dispose-Message))

;; ---- Memory Buffers --------------------------------------------------------

(define-llvm LLVM-Dispose-Memory-Buffer
  (_fun _LLVM-Memory-Buffer-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Get-Buffer-Start
  (_fun _LLVM-Memory-Buffer-Ref -> _pointer))

(define-llvm LLVM-Get-Buffer-Size
  (_fun _LLVM-Memory-Buffer-Ref -> _size))
