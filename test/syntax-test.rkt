#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/syntax
           llvm/private/safe/module)

  (test-case "macro: simple add function"
    (define-llvm-module m
      (: add (-> Int32 Int32 Int32))
      (define (add a b) (+ a b)))
    (check-equal? (call m 'add 3 4) 7))

  (test-case "macro: float multiply"
    (define-llvm-module m
      (: fmul (-> Float64 Float64 Float64))
      (define (fmul x y) (* x y)))
    (check-= (call m 'fmul 3.0 2.5) 7.5 0.0))

  (test-case "macro: if expression"
    (define-llvm-module m
      (: max (-> Int32 Int32 Int32))
      (define (max a b)
        (if (> a b) a b)))
    (check-equal? (call m 'max 10 3) 10)
    (check-equal? (call m 'max 3 10) 10))

  (test-case "macro: named let loop (factorial)"
    (define-llvm-module m
      (: fact (-> Int32 Int32))
      (define (fact n)
        (let loop ([i : Int32 n] [acc : Int32 1])
          (if (<= i 1)
              acc
              (loop (- i 1) (* acc i))))))
    (check-equal? (call m 'fact 10) 3628800))

  (test-case "macro: multiple functions"
    (define-llvm-module m
      (: double (-> Int32 Int32))
      (define (double x) (+ x x))
      (: quad (-> Int32 Int32))
      (define (quad x) (double (double x))))
    (check-equal? (call m 'double 5) 10)
    (check-equal? (call m 'quad 3) 12))

  (test-case "macro: record type"
    (define-llvm-module m
      (define-record Point ([x : Float64] [y : Float64]))
      (: get-x (-> Float64 Float64 Float64))
      (define (get-x a b)
        (Point-x (Point a b))))
    (check-= (call m 'get-x 3.0 4.0) 3.0 0.0)))
