#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "utility.rkt")

(provide LLVM-Initialize-X86-Target-Info
         LLVM-Initialize-X86-Target
         LLVM-Initialize-X86-Target-MC
         LLVM-Initialize-X86-Asm-Printer
         LLVM-Initialize-X86-Asm-Parser
         LLVM-Initialize-X86-Disassembler
         Initialize-Native-Target!
         LLVM-Get-Host-CPU-Name
         LLVM-Get-Host-CPU-Features)

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

(define-llvm LLVM-Initialize-X86-Disassembler
  (_fun -> _void))

;; ---- Host CPU detection -----------------------------------------------------

;; Returns the host CPU name (e.g., "skylake", "znver3").
;; The returned string must be freed with LLVMDisposeMessage.
(define-llvm LLVM-Get-Host-CPU-Name
  (_fun -> _pointer)
  #:wrap (lambda (proc)
           (lambda ()
             (define p (proc))
             (define s (cast p _pointer _string))
             ;; LLVMGetHostCPUName returns a malloc'd string
             (LLVM-Dispose-Message p)
             s)))

;; Returns the host CPU feature string (e.g., "+avx2,+sse4.2,...").
;; The returned string must be freed with LLVMDisposeMessage.
(define-llvm LLVM-Get-Host-CPU-Features
  (_fun -> _pointer)
  #:wrap (lambda (proc)
           (lambda ()
             (define p (proc))
             (define s (cast p _pointer _string))
             (LLVM-Dispose-Message p)
             s)))

;; Racket-level convenience matching LLVMInitializeNativeTarget behavior.
;; Also initializes the disassembler for completeness.
(define (Initialize-Native-Target!)
  (LLVM-Initialize-X86-Target-Info)
  (LLVM-Initialize-X86-Target)
  (LLVM-Initialize-X86-Target-MC)
  (LLVM-Initialize-X86-Asm-Printer)
  (LLVM-Initialize-X86-Asm-Parser)
  (LLVM-Initialize-X86-Disassembler))
