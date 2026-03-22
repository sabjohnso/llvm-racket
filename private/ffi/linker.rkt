#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt"
         "module.rkt")

(provide LLVM-Link-Modules2)

;; LLVMLinkModules2(Dest, Src) -> LLVMBool
;; Links Src into Dest.  Src is destroyed after linking.
;; Returns 0 on success, non-zero on failure.
(define-llvm LLVM-Link-Modules2
  (_fun _LLVM-Module-Ref _LLVM-Module-Ref -> _LLVM-Bool)
  #:wrap (let ()
           (lambda (proc)
             (lambda (dest src)
               (define result (proc dest src))
               (unless (zero? result)
                 (error 'LLVM-Link-Modules2 "failed to link modules"))
               ;; Src is consumed — cancel its GC finalizer.
               (cancel-module-ownership! src)))))
