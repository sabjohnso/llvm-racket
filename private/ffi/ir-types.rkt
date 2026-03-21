#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt")

(provide ;; Integer types
         LLVM-Int1-Type-In-Context
         LLVM-Int8-Type-In-Context
         LLVM-Int16-Type-In-Context
         LLVM-Int32-Type-In-Context
         LLVM-Int64-Type-In-Context
         LLVM-Int-Type-In-Context
         ;; Float types
         LLVM-Float-Type-In-Context
         LLVM-Double-Type-In-Context
         ;; Void and pointer types
         LLVM-Void-Type-In-Context
         LLVM-Pointer-Type-In-Context
         ;; Aggregate types
         LLVM-Struct-Type-In-Context
         LLVM-Struct-Create-Named
         LLVM-Struct-Set-Body
         LLVM-Array-Type
         LLVM-Vector-Type
         ;; Function types
         LLVM-Function-Type)

;; Handles into the context.  Anchor result → context (arg 0).

(define-llvm LLVM-Int1-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int8-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int16-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int32-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int64-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int-Type-In-Context
  (_fun _LLVM-Context-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Float-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Double-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Void-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Address space 0 = default.
(define-llvm LLVM-Pointer-Type-In-Context
  (_fun _LLVM-Context-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Anonymous struct.  packed = 0 for normal layout.
(define-llvm LLVM-Struct-Type-In-Context
  (_fun _LLVM-Context-Ref
        (_list i _LLVM-Type-Ref)
        _uint
        _LLVM-Bool
        -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Named struct (opaque until body is set).
(define-llvm LLVM-Struct-Create-Named
  (_fun _LLVM-Context-Ref _string -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Set the body of a named struct.
(define-llvm LLVM-Struct-Set-Body
  (_fun _LLVM-Type-Ref
        (_list i _LLVM-Type-Ref)
        _uint
        _LLVM-Bool
        -> _void))

;; Array type.  Anchor to the element type (transitively keeps context alive).
(define-llvm LLVM-Array-Type
  (_fun _LLVM-Type-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Fixed-length vector type.
(define-llvm LLVM-Vector-Type
  (_fun _LLVM-Type-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Anchor to the return type, which transitively keeps context alive.
(define-llvm LLVM-Function-Type
  (_fun _LLVM-Type-Ref
        (_list i _LLVM-Type-Ref)
        _uint
        _LLVM-Bool
        -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))
