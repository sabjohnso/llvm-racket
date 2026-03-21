#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "enums.rkt"
         "core.rkt")

(provide LLVM-Get-Default-Target-Triple
         LLVM-Get-Target-From-Triple
         LLVM-Create-Target-Machine
         LLVM-Dispose-Target-Machine
         LLVM-Target-Machine-Emit-To-Memory-Buffer
         LLVM-Target-Machine-Emit-To-File)

(define-llvm LLVM-Get-Default-Target-Triple
  (_fun -> _pointer)
  #:wrap (allocator LLVM-Dispose-Message))

(define-llvm LLVM-Get-Target-From-Triple
  (_fun _string
        (target : (_ptr o _LLVM-Target-Ref))
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result target err)))

(define-llvm LLVM-Dispose-Target-Machine
  (_fun _LLVM-Target-Machine-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Target-Machine
  (_fun _LLVM-Target-Ref            ; target
        _string                     ; triple
        _string                     ; cpu
        _string                     ; features
        _LLVM-Code-Gen-Opt-Level    ; opt level
        _LLVM-Reloc-Mode            ; reloc mode
        _LLVM-Code-Model            ; code model
        -> _LLVM-Target-Machine-Ref)
  #:wrap (allocator LLVM-Dispose-Target-Machine))

;; Emit module as assembly or object code to a memory buffer.
;; The returned buffer is a new allocation — annotated accordingly.
(define-llvm LLVM-Target-Machine-Emit-To-Memory-Buffer
  (_fun _LLVM-Target-Machine-Ref
        _LLVM-Module-Ref
        _LLVM-Code-Gen-File-Type
        (err : (_ptr o _pointer))
        (buf : (_ptr o _LLVM-Memory-Buffer-Ref))
        -> (result : _LLVM-Bool)
        -> (values result buf err)))

;; Emit module as assembly or object code to a file.
(define-llvm LLVM-Target-Machine-Emit-To-File
  (_fun _LLVM-Target-Machine-Ref
        _LLVM-Module-Ref
        _string
        _LLVM-Code-Gen-File-Type
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result err)))
