#lang racket/base

(module+ test
  (require rackunit
           llvm/safe)

  ;; Verify all public APIs are accessible through llvm/safe

  (test-case "llvm/safe: macro layer works"
    (define-llvm-module m
      (define (add [a : Int32] [b : Int32]) (+ a b)))
    (check-equal? (call m add 3 4) 7))

  (test-case "llvm/safe: runtime API works"
    (define m (make-llvm-module
               (func 'mul (formals (variable 'a i32) (variable 'b i32))
                          (body ((op '*) (ref 'a) (ref 'b))))))
    (check-equal? (call m mul 6 7) 42))

  (test-case "llvm/safe: record types via macro"
    (define-llvm-module m
      (struct Point ([x : Float64] [y : Float64]))
      (define (get-x [a : Float64] [b : Float64])
        (Point-x (Point a b))))
    (check-= (call m get-x 3.0 4.0) 3.0 0.0))

  (test-case "llvm/safe: union and match via macro"
    (define-llvm-module m
      (union Opt
        [Some ([value : Int32])]
        [None])
      (define (unwrap [x : Int32])
        (match (Some x)
          [(Some v) v]
          [(None) 0])))
    (check-equal? (call m unwrap 42) 42))

  (test-case "llvm/safe: primitive types available"
    (check-not-false i1)
    (check-not-false i8)
    (check-not-false i16)
    (check-not-false i32)
    (check-not-false i64)
    (check-not-false f32)
    (check-not-false f64)
    (check-not-false void-type)))
