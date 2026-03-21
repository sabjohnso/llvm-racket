#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt")

(provide LLVM-Context-Create
         LLVM-Context-Dispose
         LLVM-Module-Create-With-Name-In-Context
         LLVM-Dispose-Module
         LLVM-Int32-Type-In-Context
         LLVM-Function-Type
         LLVM-Add-Function
         LLVM-Get-Param
         LLVM-Append-Basic-Block-In-Context
         LLVM-Create-Builder-In-Context
         LLVM-Position-Builder-At-End
         LLVM-Build-Add
         LLVM-Build-Ret
         LLVM-Dispose-Builder
         LLVM-Print-Module-To-String
         LLVM-Dispose-Message)

;; Context
(define-llvm LLVM-Context-Create
  (_fun -> _LLVM-Context-Ref)
)

(define-llvm LLVM-Context-Dispose
  (_fun _LLVM-Context-Ref -> _void))

;; Module
(define-llvm LLVM-Module-Create-With-Name-In-Context
  (_fun _string _LLVM-Context-Ref -> _LLVM-Module-Ref))

(define-llvm LLVM-Dispose-Module
  (_fun _LLVM-Module-Ref -> _void))

;; Types
(define-llvm LLVM-Int32-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref))

(define-llvm LLVM-Function-Type
  (_fun _LLVM-Type-Ref              ; return type
        (_list i _LLVM-Type-Ref)    ; param types
        _uint                       ; param count
        _LLVM-Bool                  ; is-vararg
        -> _LLVM-Type-Ref))

;; Functions
(define-llvm LLVM-Add-Function
  (_fun _LLVM-Module-Ref _string _LLVM-Type-Ref -> _LLVM-Value-Ref))

(define-llvm LLVM-Get-Param
  (_fun _LLVM-Value-Ref _uint -> _LLVM-Value-Ref))

;; Basic blocks
(define-llvm LLVM-Append-Basic-Block-In-Context
  (_fun _LLVM-Context-Ref _LLVM-Value-Ref _string -> _LLVM-Basic-Block-Ref))

;; Builder
(define-llvm LLVM-Create-Builder-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Builder-Ref))

(define-llvm LLVM-Position-Builder-At-End
  (_fun _LLVM-Builder-Ref _LLVM-Basic-Block-Ref -> _void))

(define-llvm LLVM-Build-Add
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref))

(define-llvm LLVM-Build-Ret
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref -> _LLVM-Value-Ref))

(define-llvm LLVM-Dispose-Builder
  (_fun _LLVM-Builder-Ref -> _void))

;; Utility
(define-llvm LLVM-Print-Module-To-String
  (_fun _LLVM-Module-Ref -> _pointer))

(define-llvm LLVM-Dispose-Message
  (_fun _pointer -> _void))
