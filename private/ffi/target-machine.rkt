#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt"
         "enums.rkt")

(provide LLVM-Get-Default-Target-Triple
         LLVM-Get-Target-From-Triple
         LLVM-Create-Target-Machine
         LLVM-Dispose-Target-Machine)

(define-llvm LLVM-Get-Default-Target-Triple
  (_fun -> _pointer))

(define-llvm LLVM-Get-Target-From-Triple
  (_fun _string
        (target : (_ptr o _LLVM-Target-Ref))
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result target err)))

(define-llvm LLVM-Create-Target-Machine
  (_fun _LLVM-Target-Ref            ; target
        _string                     ; triple
        _string                     ; cpu
        _string                     ; features
        _LLVM-Code-Gen-Opt-Level    ; opt level
        _LLVM-Reloc-Mode            ; reloc mode
        _LLVM-Code-Model            ; code model
        -> _LLVM-Target-Machine-Ref))

(define-llvm LLVM-Dispose-Target-Machine
  (_fun _LLVM-Target-Machine-Ref -> _void))
