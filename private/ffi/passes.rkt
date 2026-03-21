#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide ;; New pass manager (LLVM 13+)
         LLVM-Run-Passes
         LLVM-Create-Pass-Builder-Options
         LLVM-Dispose-Pass-Builder-Options
         ;; Legacy pass manager
         LLVM-Create-Pass-Manager
         LLVM-Create-Function-Pass-Manager-For-Module
         LLVM-Dispose-Pass-Manager
         LLVM-Run-Pass-Manager
         LLVM-Initialize-Function-Pass-Manager
         LLVM-Run-Function-Pass-Manager
         LLVM-Finalize-Function-Pass-Manager
         ;; Legacy transform passes
         LLVM-Add-Instruction-Combining-Pass
         LLVM-Add-Reassociate-Pass
         LLVM-Add-GVN-Pass
         LLVM-Add-CFG-Simplification-Pass
         LLVM-Add-Promote-Memory-To-Register-Pass
         LLVM-Add-Scalar-Repl-Aggregates-Pass-SSA)

;; ---- LLVMError helpers (used by new pass manager) -------------------------
;; LLVMRunPasses returns LLVMErrorRef (null on success, error on failure).

(define LLVMGetErrorMessage
  (get-ffi-obj "LLVMGetErrorMessage" llvm-lib
               (_fun _pointer -> _pointer)))

(define LLVMDisposeErrorMessage
  (get-ffi-obj "LLVMDisposeErrorMessage" llvm-lib
               (_fun _pointer -> _void)))

(define (check-llvm-error-ref who err-ref)
  (when err-ref
    (define msg-ptr (LLVMGetErrorMessage err-ref))
    (define msg (if msg-ptr (cast msg-ptr _pointer _string) "unknown LLVM error"))
    (when msg-ptr (LLVMDisposeErrorMessage msg-ptr))
    (error who "~a" msg)))

;; ---- New Pass Manager (LLVM 13+) ------------------------------------------

(define-llvm LLVM-Dispose-Pass-Builder-Options
  (_fun _LLVM-Pass-Builder-Options-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Pass-Builder-Options
  (_fun -> _LLVM-Pass-Builder-Options-Ref)
  #:wrap (allocator LLVM-Dispose-Pass-Builder-Options))

;; LLVMRunPasses returns LLVMErrorRef (null = success).
;; We wrap to raise exn:fail on error.
(define-llvm LLVM-Run-Passes
  (_fun _LLVM-Module-Ref
        _string                            ; pass pipeline description
        _LLVM-Target-Machine-Ref
        _LLVM-Pass-Builder-Options-Ref
        -> _pointer)                       ; LLVMErrorRef (null = success)
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod passes tm opts)
               (define err (proc mod passes tm opts))
               (check-llvm-error-ref 'LLVM-Run-Passes err)))))

;; ---- Legacy Pass Manager --------------------------------------------------

(define-llvm LLVM-Dispose-Pass-Manager
  (_fun _LLVM-Pass-Manager-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Pass-Manager
  (_fun -> _LLVM-Pass-Manager-Ref)
  #:wrap (allocator LLVM-Dispose-Pass-Manager))

(define-llvm LLVM-Create-Function-Pass-Manager-For-Module
  (_fun _LLVM-Module-Ref -> _LLVM-Pass-Manager-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Pass-Manager 0))

(define-llvm LLVM-Run-Pass-Manager
  (_fun _LLVM-Pass-Manager-Ref _LLVM-Module-Ref -> _LLVM-Bool))

(define-llvm LLVM-Initialize-Function-Pass-Manager
  (_fun _LLVM-Pass-Manager-Ref -> _LLVM-Bool))

(define-llvm LLVM-Run-Function-Pass-Manager
  (_fun _LLVM-Pass-Manager-Ref _LLVM-Value-Ref -> _LLVM-Bool))

(define-llvm LLVM-Finalize-Function-Pass-Manager
  (_fun _LLVM-Pass-Manager-Ref -> _LLVM-Bool))

;; ---- Legacy Transform Passes ----------------------------------------------
;; Each takes a PassManagerRef and adds a pass to the pipeline.

(define _add-pass (_fun _LLVM-Pass-Manager-Ref -> _void))

(define-llvm LLVM-Add-Instruction-Combining-Pass _add-pass)
(define-llvm LLVM-Add-Reassociate-Pass           _add-pass)
(define-llvm LLVM-Add-GVN-Pass                   _add-pass)
(define-llvm LLVM-Add-CFG-Simplification-Pass    _add-pass)
(define-llvm LLVM-Add-Promote-Memory-To-Register-Pass _add-pass)
(define-llvm LLVM-Add-Scalar-Repl-Aggregates-Pass-SSA _add-pass)
