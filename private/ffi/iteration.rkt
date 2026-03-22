#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt")

(provide ;; Low-level iteration
         LLVM-Get-First-Function
         LLVM-Get-Next-Function
         LLVM-Get-First-Global
         LLVM-Get-Next-Global
         LLVM-Get-First-Basic-Block
         LLVM-Get-Next-Basic-Block
         LLVM-Get-First-Instruction
         LLVM-Get-Next-Instruction
         ;; Value inspection
         LLVM-Get-Value-Name
         LLVM-Get-Instruction-Opcode
         ;; Racket-idiomatic helpers
         LLVM-Module-Functions
         LLVM-Module-Globals
         LLVM-Function-Basic-Blocks
         LLVM-Basic-Block-Instructions)

;; ---- Function iteration ----------------------------------------------------

(define-llvm LLVM-Get-First-Function
  (_fun _LLVM-Module-Ref -> _LLVM-Value-Ref/null))

(define-llvm LLVM-Get-Next-Function
  (_fun _LLVM-Value-Ref -> _LLVM-Value-Ref/null))

;; ---- Global iteration ------------------------------------------------------

(define-llvm LLVM-Get-First-Global
  (_fun _LLVM-Module-Ref -> _LLVM-Value-Ref/null))

(define-llvm LLVM-Get-Next-Global
  (_fun _LLVM-Value-Ref -> _LLVM-Value-Ref/null))

;; ---- Basic block iteration -------------------------------------------------

(define-llvm LLVM-Get-First-Basic-Block
  (_fun _LLVM-Value-Ref -> _LLVM-Basic-Block-Ref/null))

(define-llvm LLVM-Get-Next-Basic-Block
  (_fun _LLVM-Basic-Block-Ref -> _LLVM-Basic-Block-Ref/null))

;; ---- Instruction iteration -------------------------------------------------

(define-llvm LLVM-Get-First-Instruction
  (_fun _LLVM-Basic-Block-Ref -> _LLVM-Value-Ref/null))

(define-llvm LLVM-Get-Next-Instruction
  (_fun _LLVM-Value-Ref -> _LLVM-Value-Ref/null))

;; ---- Value inspection ------------------------------------------------------

;; LLVMGetValueName2 returns const char* + length out-param.
;; We just use _string which copies.
(define-llvm LLVM-Get-Value-Name
  (_fun _LLVM-Value-Ref (len : (_ptr o _size)) -> _string)
  #:c-id LLVMGetValueName2)

(define-llvm LLVM-Get-Instruction-Opcode
  (_fun _LLVM-Value-Ref -> _int))

;; ---- Racket-idiomatic helpers ----------------------------------------------

(define (collect-list get-first get-next start)
  (let loop ([cur (get-first start)] [acc '()])
    (if cur
        (loop (get-next cur) (cons cur acc))
        (reverse acc))))

(define (LLVM-Module-Functions mod)
  (collect-list LLVM-Get-First-Function LLVM-Get-Next-Function mod))

(define (LLVM-Module-Globals mod)
  (collect-list LLVM-Get-First-Global LLVM-Get-Next-Global mod))

(define (LLVM-Function-Basic-Blocks fn)
  (collect-list LLVM-Get-First-Basic-Block LLVM-Get-Next-Basic-Block fn))

(define (LLVM-Basic-Block-Instructions bb)
  (collect-list LLVM-Get-First-Instruction LLVM-Get-Next-Instruction bb))
