#lang racket/base

(require ffi/unsafe
         "lib.rkt")

(provide LLVM-Initialize-X86-Target-Info
         LLVM-Initialize-X86-Target
         LLVM-Initialize-X86-Target-MC
         LLVM-Initialize-X86-Asm-Printer
         LLVM-Initialize-X86-Asm-Parser
         Initialize-Native-Target!)

(define-llvm LLVM-Initialize-X86-Target-Info
  (_fun -> _void))

(define-llvm LLVM-Initialize-X86-Target
  (_fun -> _void))

(define-llvm LLVM-Initialize-X86-Target-MC
  (_fun -> _void))

(define-llvm LLVM-Initialize-X86-Asm-Printer
  (_fun -> _void))

(define-llvm LLVM-Initialize-X86-Asm-Parser
  (_fun -> _void))

;; Racket-level convenience matching LLVMInitializeNativeTarget behavior.
(define (Initialize-Native-Target!)
  (LLVM-Initialize-X86-Target-Info)
  (LLVM-Initialize-X86-Target)
  (LLVM-Initialize-X86-Target-MC)
  (LLVM-Initialize-X86-Asm-Printer)
  (LLVM-Initialize-X86-Asm-Parser))
