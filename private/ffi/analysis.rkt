#lang racket/base

(require ffi/unsafe
         "lib.rkt"
         "types.rkt"
         "enums.rkt")

(provide LLVM-Verify-Module)

(define-llvm LLVM-Verify-Module
  (_fun _LLVM-Module-Ref
        _LLVM-Verifier-Failure-Action
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod action)
               (define-values (result err) (proc mod action))
               (check-llvm-error 'LLVM-Verify-Module result err)))))
