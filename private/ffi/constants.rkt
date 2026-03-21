#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt")

(provide ;; Scalar constants
         LLVM-Const-Int
         LLVM-Const-Real
         LLVM-Const-Null
         LLVM-Const-All-Ones
         LLVM-Get-Undef
         ;; Aggregate constants
         LLVM-Const-String-In-Context
         LLVM-Const-String
         LLVM-Const-Array
         LLVM-Const-Struct
         LLVM-Const-Named-Struct
         ;; Constant expressions
         LLVM-Const-GEP2
         LLVM-Const-Bit-Cast
         LLVM-Const-Int-To-Ptr
         LLVM-Const-Ptr-To-Int)

;; ---- Scalar Constants ------------------------------------------------------
;; These return Value handles anchored to their type (transitively to context).

(define-llvm LLVM-Const-Int
  (_fun _LLVM-Type-Ref _ullong _LLVM-Bool -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-Real
  (_fun _LLVM-Type-Ref _double -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-Null
  (_fun _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-All-Ones
  (_fun _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Get-Undef
  (_fun _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

;; ---- Aggregate Constants ---------------------------------------------------

(define-llvm LLVM-Const-String-In-Context
  (_fun _LLVM-Context-Ref _string _uint _LLVM-Bool -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-String
  (_fun _string _uint _LLVM-Bool -> _LLVM-Value-Ref))

(define-llvm LLVM-Const-Array
  (_fun _LLVM-Type-Ref (_list i _LLVM-Value-Ref) _uint -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-Struct
  (_fun (_list i _LLVM-Value-Ref) _uint _LLVM-Bool -> _LLVM-Value-Ref))

(define-llvm LLVM-Const-Named-Struct
  (_fun _LLVM-Type-Ref (_list i _LLVM-Value-Ref) _uint -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

;; ---- Constant Expressions --------------------------------------------------

(define-llvm LLVM-Const-GEP2
  (_fun _LLVM-Type-Ref _LLVM-Value-Ref (_list i _LLVM-Value-Ref) _uint -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Const-Bit-Cast
  (_fun _LLVM-Value-Ref _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 1))

(define-llvm LLVM-Const-Int-To-Ptr
  (_fun _LLVM-Value-Ref _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 1))

(define-llvm LLVM-Const-Ptr-To-Int
  (_fun _LLVM-Value-Ref _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 1))
