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
         _LLVM-Orc-LLJIT-Ref _LLVM-Orc-LLJIT-Ref/null
         _LLVM-Orc-JIT-Dylib-Ref _LLVM-Orc-JIT-Dylib-Ref/null
         _LLVM-Orc-Thread-Safe-Context-Ref _LLVM-Orc-Thread-Safe-Context-Ref/null
         _LLVM-Orc-Thread-Safe-Module-Ref _LLVM-Orc-Thread-Safe-Module-Ref/null
         _LLVM-Orc-Execution-Session-Ref _LLVM-Orc-Execution-Session-Ref/null
         _LLVM-Orc-Definition-Generator-Ref _LLVM-Orc-Definition-Generator-Ref/null
         _LLVM-Object-File-Ref _LLVM-Object-File-Ref/null
         _LLVM-Section-Iterator-Ref _LLVM-Section-Iterator-Ref/null
         _LLVM-Symbol-Iterator-Ref _LLVM-Symbol-Iterator-Ref/null
         _LLVM-Relocation-Iterator-Ref _LLVM-Relocation-Iterator-Ref/null
         _LLVM-DI-Builder-Ref _LLVM-DI-Builder-Ref/null
         _LLVM-Metadata-Ref _LLVM-Metadata-Ref/null
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
(define-cpointer-type _LLVM-Orc-LLJIT-Ref)
(define-cpointer-type _LLVM-Orc-JIT-Dylib-Ref)
(define-cpointer-type _LLVM-Orc-Thread-Safe-Context-Ref)
(define-cpointer-type _LLVM-Orc-Thread-Safe-Module-Ref)
(define-cpointer-type _LLVM-Orc-Execution-Session-Ref)
(define-cpointer-type _LLVM-Orc-Definition-Generator-Ref)
(define-cpointer-type _LLVM-Object-File-Ref)
(define-cpointer-type _LLVM-Section-Iterator-Ref)
(define-cpointer-type _LLVM-Symbol-Iterator-Ref)
(define-cpointer-type _LLVM-Relocation-Iterator-Ref)

(define-cpointer-type _LLVM-DI-Builder-Ref)
(define-cpointer-type _LLVM-Metadata-Ref)

(define _LLVM-Bool _int)
