#lang racket/base

(require "repr.rkt")

(provide llvm-library llvm-library? llvm-library-name llvm-library-decls
         math-lib)

;; ---- Library type -----------------------------------------------------------

(struct llvm-library (name decls) #:transparent)

;; ---- Math library -----------------------------------------------------------
;; LLVM intrinsics for common math operations on Float64.

(define math-lib
  (llvm-library 'math
    (list
     (intrinsic-func 'sqrt  "llvm.sqrt.f64"    (list f64) f64)
     (intrinsic-func 'abs   "llvm.fabs.f64"    (list f64) f64)
     (intrinsic-func 'pow   "llvm.pow.f64"     (list f64 f64) f64)
     (intrinsic-func 'floor "llvm.floor.f64"   (list f64) f64)
     (intrinsic-func 'ceil  "llvm.ceil.f64"    (list f64) f64)
     (intrinsic-func 'round "llvm.round.f64"   (list f64) f64)
     (intrinsic-func 'sin   "llvm.sin.f64"     (list f64) f64)
     (intrinsic-func 'cos   "llvm.cos.f64"     (list f64) f64)
     (intrinsic-func 'exp   "llvm.exp.f64"     (list f64) f64)
     (intrinsic-func 'log   "llvm.log.f64"     (list f64) f64)
     (intrinsic-func 'log2  "llvm.log2.f64"    (list f64) f64)
     (intrinsic-func 'log10 "llvm.log10.f64"   (list f64) f64)
     (intrinsic-func 'min   "llvm.minnum.f64"  (list f64 f64) f64)
     (intrinsic-func 'max   "llvm.maxnum.f64"  (list f64 f64) f64))))
