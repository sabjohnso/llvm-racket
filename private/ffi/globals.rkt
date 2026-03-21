#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt"
         "enums.rkt")

(provide ;; Global variables
         LLVM-Add-Global
         LLVM-Set-Initializer
         LLVM-Get-Initializer
         LLVM-Set-Global-Constant
         LLVM-Set-Alignment
         ;; Linkage
         LLVM-Set-Linkage
         LLVM-Get-Linkage
         ;; Visibility
         LLVM-Set-Visibility
         LLVM-Get-Visibility
         ;; Function attributes
         LLVM-Add-Attribute-At-Index
         LLVM-Create-Enum-Attribute
         LLVM-Create-String-Attribute
         LLVM-Set-Function-Call-Conv)

;; ---- Global Variables ------------------------------------------------------
;; Globals are handles into the module.  Anchor result → module.

(define-llvm LLVM-Add-Global
  (_fun _LLVM-Module-Ref _LLVM-Type-Ref _string -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Set-Initializer
  (_fun _LLVM-Value-Ref _LLVM-Value-Ref -> _void))

(define-llvm LLVM-Get-Initializer
  (_fun _LLVM-Value-Ref -> _LLVM-Value-Ref/null))

(define-llvm LLVM-Set-Global-Constant
  (_fun _LLVM-Value-Ref _LLVM-Bool -> _void))

(define-llvm LLVM-Set-Alignment
  (_fun _LLVM-Value-Ref _uint -> _void))

;; ---- Linkage ---------------------------------------------------------------

(define-llvm LLVM-Set-Linkage
  (_fun _LLVM-Value-Ref _LLVM-Linkage -> _void))

(define-llvm LLVM-Get-Linkage
  (_fun _LLVM-Value-Ref -> _LLVM-Linkage))

;; ---- Visibility ------------------------------------------------------------

(define-llvm LLVM-Set-Visibility
  (_fun _LLVM-Value-Ref _LLVM-Visibility -> _void))

(define-llvm LLVM-Get-Visibility
  (_fun _LLVM-Value-Ref -> _LLVM-Visibility))

;; ---- Function Attributes ---------------------------------------------------

(define-llvm LLVM-Create-Enum-Attribute
  (_fun _LLVM-Context-Ref _uint _uint64 -> _pointer)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Create-String-Attribute
  (_fun _LLVM-Context-Ref
        _string _uint      ; key, key-length
        _string _uint      ; value, value-length
        -> _pointer)
  #:wrap (prevent-gc-wrap 0))

;; LLVMAttributeIndex is unsigned int.
(define-llvm LLVM-Add-Attribute-At-Index
  (_fun _LLVM-Value-Ref _uint _pointer -> _void))

(define-llvm LLVM-Set-Function-Call-Conv
  (_fun _LLVM-Value-Ref _uint -> _void))
