#lang info
(define collection "llvm")
(define deps '("base"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/llvm.scrbl" ())))
(define pkg-desc "LLVM bindings for Racket via the LLVM C API")
(define version "0.0")
(define pkg-authors '(sbj))
(define license '(Apache-2.0 OR MIT))
