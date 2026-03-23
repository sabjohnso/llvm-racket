#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/module)

  (test-case "make-llvm-module and call: add(3, 4) = 7"
    (define m (make-llvm-module
               (func 'add (formals (variable 'a i32) (variable 'b i32))
                          (body ((op '+) (ref 'a) (ref 'b))))))
    (check-equal? (call m 'add 3 4) 7))

  (test-case "make-llvm-module and call: float multiply"
    (define m (make-llvm-module
               (func 'fmul (formals (variable 'x f64) (variable 'y f64))
                           (body ((op '*) (ref 'x) (ref 'y))))))
    (check-= (call m 'fmul 3.0 2.5) 7.5 0.0))

  (test-case "call: factorial(10) = 3628800"
    (define m (make-llvm-module
               (func 'fact (formals (variable 'n i32))
                           (body
                            (named-bindings 'loop
                              (list (bind (variable 'i i32) (ref 'n))
                                    (bind (variable 'acc i32) (lit 1 i32)))
                              (body
                               (if-form ((icmp '<=) (ref 'i) (lit 1 i32))
                                        (ref 'acc)
                                        (app (ref 'loop)
                                             ((op '-) (ref 'i) (lit 1 i32))
                                             ((op '*) (ref 'acc) (ref 'i))))))))))
    (check-equal? (call m 'fact 10) 3628800))

  (test-case "call: max(10, 3) = 10"
    (define m (make-llvm-module
               (func 'max (formals (variable 'a i32) (variable 'b i32))
                          (body
                           (if-form ((icmp '>) (ref 'a) (ref 'b))
                                    (ref 'a)
                                    (ref 'b))))))
    (check-equal? (call m 'max 10 3) 10)
    (check-equal? (call m 'max 3 10) 10))

  (test-case "call: cross-function calls"
    (define m (make-llvm-module
               (func 'double (formals (variable 'x i32))
                             (body ((op '+) (ref 'x) (ref 'x))))
               (func 'quad (formals (variable 'x i32))
                           (body (app (ref 'double)
                                      (app (ref 'double) (ref 'x)))))))
    (check-equal? (call m 'double 5) 10)
    (check-equal? (call m 'quad 3) 12))

  (test-case "call: unknown function raises"
    (define m (make-llvm-module
               (func 'add (formals (variable 'a i32) (variable 'b i32))
                          (body ((op '+) (ref 'a) (ref 'b))))))
    (check-exn exn:fail?
               (lambda () (call m 'nonexistent 1 2)))))
