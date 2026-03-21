#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide ;; BitWriter
         LLVM-Write-Bitcode-To-File
         LLVM-Write-Bitcode-To-Memory-Buffer
         ;; BitReader
         LLVM-Parse-Bitcode-In-Context2
         LLVM-Parse-Bitcode-File
         ;; IRReader
         LLVM-Parse-IR-In-Context
         ;; Memory buffer construction
         LLVM-Create-Memory-Buffer-With-Contents-Of-File
         LLVM-Create-Memory-Buffer-With-Memory-Range
         ;; Module utilities
         LLVM-Clone-Module
         LLVM-Set-Target
         LLVM-Get-Target
         LLVM-Set-Data-Layout
         LLVM-Get-Data-Layout)

;; We need Dispose-Module and Dispose-Memory-Buffer deallocators
;; for registering out-param results.
(require "utility.rkt"
         "module.rkt")

;; ---- BitWriter -------------------------------------------------------------

;; Returns 0 on success, non-zero on failure.
(define-llvm LLVM-Write-Bitcode-To-File
  (_fun _LLVM-Module-Ref _string -> _int)
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod path)
               (define result (proc mod path))
               (unless (zero? result)
                 (error 'LLVM-Write-Bitcode-To-File
                        "failed to write bitcode to ~a" path))))))



(define-llvm LLVM-Write-Bitcode-To-Memory-Buffer
  (_fun _LLVM-Module-Ref -> _LLVM-Memory-Buffer-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod)
               (define buf (proc mod))
               (when buf (register-memory-buffer! buf))
               buf))))

;; ---- BitReader -------------------------------------------------------------

(define register-module!
  (make-register-allocation LLVM-Dispose-Module))

;; LLVMParseBitcodeInContext2(ctx, membuf, &outmod) -> LLVMBool
;; No error message out-param — just success/failure.
(define-llvm LLVM-Parse-Bitcode-In-Context2
  (_fun _LLVM-Context-Ref
        _LLVM-Memory-Buffer-Ref
        (mod : (_ptr o _LLVM-Module-Ref))
        -> (result : _LLVM-Bool)
        -> (values result mod))
  #:wrap (let ()
           (lambda (proc)
             (lambda (ctx buf)
               (define-values (result mod) (proc ctx buf))
               (unless (zero? result)
                 (error 'LLVM-Parse-Bitcode-In-Context2
                        "failed to parse bitcode"))
               (register-module! mod)
               (prevent-gc! mod ctx)
               mod))))

;; Convenience: read bitcode from a file path.
(define (LLVM-Parse-Bitcode-File ctx path)
  (define buf (LLVM-Create-Memory-Buffer-With-Contents-Of-File path))
  (LLVM-Parse-Bitcode-In-Context2 ctx buf))

;; ---- IRReader --------------------------------------------------------------

;; LLVMParseIRInContext(ctx, membuf, &outmod, &errmsg) -> LLVMBool
;; Note: this consumes the memory buffer.
(define-llvm LLVM-Parse-IR-In-Context
  (_fun _LLVM-Context-Ref
        _LLVM-Memory-Buffer-Ref
        (mod : (_ptr o _LLVM-Module-Ref))
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result mod err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (ctx buf)
               (define-values (result mod err) (proc ctx buf))
               (check-llvm-error 'LLVM-Parse-IR-In-Context result err)
               (register-module! mod)
               (prevent-gc! mod ctx)
               mod))))

;; ---- Memory Buffer Construction -------------------------------------------

(define-llvm LLVM-Create-Memory-Buffer-With-Contents-Of-File
  (_fun _string
        (buf : (_ptr o _LLVM-Memory-Buffer-Ref))
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result buf err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (path)
               (define-values (result buf err) (proc path))
               (check-llvm-error 'LLVM-Create-Memory-Buffer-With-Contents-Of-File result err)
               (register-memory-buffer! buf)
               buf))))

(define-llvm LLVM-Create-Memory-Buffer-With-Memory-Range
  (_fun _string _size _string _LLVM-Bool -> _LLVM-Memory-Buffer-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (data len name null-terminate?)
               (define buf (proc data len name null-terminate?))
               (when buf (register-memory-buffer! buf))
               buf))))

;; ---- Module Utilities ------------------------------------------------------

;; Clone returns a new module.  Anchor to the original module's context
;; (transitively via the original module's prevent-gc chain).
(define-llvm LLVM-Clone-Module
  (_fun _LLVM-Module-Ref -> _LLVM-Module-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod)
               (define clone (proc mod))
               (when clone
                 (register-module! clone)
                 (prevent-gc! clone mod))
               clone))))

;; Target triple — returns const char* (LLVM-owned, do not free).
(define-llvm LLVM-Set-Target
  (_fun _LLVM-Module-Ref _string -> _void))

(define-llvm LLVM-Get-Target
  (_fun _LLVM-Module-Ref -> _string))

;; Data layout — returns const char* (LLVM-owned, do not free).
(define-llvm LLVM-Set-Data-Layout
  (_fun _LLVM-Module-Ref _string -> _void))

;; Use LLVMGetDataLayoutStr (not the deprecated LLVMGetDataLayout).
(define LLVM-Get-Data-Layout
  (let ([raw (get-ffi-obj "LLVMGetDataLayoutStr" llvm-lib
                          (_fun _LLVM-Module-Ref -> _string))])
    raw))
