#lang racket/base

(require ffi/unsafe)

(provide _LLVM-Context-Ref _LLVM-Context-Ref/null
         _LLVM-Module-Ref _LLVM-Module-Ref/null
         _LLVM-Type-Ref _LLVM-Type-Ref/null
         _LLVM-Value-Ref _LLVM-Value-Ref/null
         _LLVM-Basic-Block-Ref _LLVM-Basic-Block-Ref/null
         _LLVM-Builder-Ref _LLVM-Builder-Ref/null
         _LLVM-Execution-Engine-Ref _LLVM-Execution-Engine-Ref/null
         _LLVM-Generic-Value-Ref _LLVM-Generic-Value-Ref/null
         _LLVM-Pass-Manager-Ref _LLVM-Pass-Manager-Ref/null
         _LLVM-Memory-Buffer-Ref _LLVM-Memory-Buffer-Ref/null
         _LLVM-MCJIT-Memory-Manager-Ref _LLVM-MCJIT-Memory-Manager-Ref/null
         _LLVM-Target-Ref _LLVM-Target-Ref/null
         _LLVM-Target-Machine-Ref _LLVM-Target-Machine-Ref/null
         _LLVM-Pass-Builder-Options-Ref _LLVM-Pass-Builder-Options-Ref/null
         _LLVM-Bool)

(define-cpointer-type _LLVM-Context-Ref)
(define-cpointer-type _LLVM-Module-Ref)
(define-cpointer-type _LLVM-Type-Ref)
(define-cpointer-type _LLVM-Value-Ref)
(define-cpointer-type _LLVM-Basic-Block-Ref)
(define-cpointer-type _LLVM-Builder-Ref)
(define-cpointer-type _LLVM-Execution-Engine-Ref)
(define-cpointer-type _LLVM-Generic-Value-Ref)
(define-cpointer-type _LLVM-Pass-Manager-Ref)
(define-cpointer-type _LLVM-Memory-Buffer-Ref)
(define-cpointer-type _LLVM-MCJIT-Memory-Manager-Ref)
(define-cpointer-type _LLVM-Target-Ref)
(define-cpointer-type _LLVM-Target-Machine-Ref)

(define-cpointer-type _LLVM-Pass-Builder-Options-Ref)

(define _LLVM-Bool _int)
