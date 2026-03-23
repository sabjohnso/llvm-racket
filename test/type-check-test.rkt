#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/type-check)

  ;; ---- Operator registry ----------------------------------------------------

  (test-case "arithmetic operators resolve to correct result types"
    (check-equal? (op-result-type '+ i32 i32) i32)
    (check-equal? (op-result-type '+ f64 f64) f64)
    (check-equal? (op-result-type '- i32 i32) i32)
    (check-equal? (op-result-type '* f64 f64) f64)
    (check-equal? (op-result-type '/ i32 i32) i32)
    (check-equal? (op-result-type '/ f64 f64) f64))

  (test-case "unary operators"
    (check-equal? (op-result-type 'neg i32) i32)
    (check-equal? (op-result-type 'neg f64) f64))

  (test-case "bitwise operators"
    (check-equal? (op-result-type 'bit-and i32 i32) i32)
    (check-equal? (op-result-type 'bit-or i32 i32) i32)
    (check-equal? (op-result-type 'bit-xor i32 i32) i32)
    (check-equal? (op-result-type 'bit-not i32) i32)
    (check-equal? (op-result-type 'shl i32 i32) i32)
    (check-equal? (op-result-type 'shr i32 i32) i32))

  (test-case "comparison operators return i1"
    (check-equal? (icmp-result-type '<= i32 i32) i1)
    (check-equal? (icmp-result-type '= i32 i32) i1)
    (check-equal? (fcmp-result-type '< f64 f64) i1))

  (test-case "invalid operator raises"
    (check-exn exn:fail?
               (lambda () (op-result-type '+ i32 f64)))
    (check-exn exn:fail?
               (lambda () (op-result-type 'bit-and f64 f64))))

  ;; ---- Type inference -------------------------------------------------------

  (test-case "infer literal type"
    (check-equal? (infer-type (lit 42 i32) '()) i32)
    (check-equal? (infer-type (lit 3.14 f64) '()) f64))

  (test-case "infer variable reference type from environment"
    (define env (list (cons 'x i32) (cons 'y f64)))
    (check-equal? (infer-type (ref 'x) env) i32)
    (check-equal? (infer-type (ref 'y) env) f64))

  (test-case "unbound variable raises"
    (check-exn exn:fail?
               (lambda () (infer-type (ref 'z) '()))))

  (test-case "infer operator application type"
    (define env (list (cons 'a i32) (cons 'b i32)))
    (check-equal? (infer-type ((op '+) (ref 'a) (ref 'b)) env) i32))

  (test-case "infer comparison type"
    (define env (list (cons 'a i32) (cons 'b i32)))
    (check-equal? (infer-type ((icmp '<=) (ref 'a) (ref 'b)) env) i1))

  (test-case "infer if-form type"
    (define env (list (cons 'c i1) (cons 'a i32) (cons 'b i32)))
    (check-equal? (infer-type (if-form (ref 'c) (ref 'a) (ref 'b)) env) i32))

  (test-case "if-form with non-boolean condition raises"
    (define env (list (cons 'c i32) (cons 'a i32) (cons 'b i32)))
    (check-exn exn:fail?
               (lambda () (infer-type (if-form (ref 'c) (ref 'a) (ref 'b)) env))))

  (test-case "if-form with mismatched branches raises"
    (define env (list (cons 'c i1) (cons 'a i32) (cons 'b f64)))
    (check-exn exn:fail?
               (lambda () (infer-type (if-form (ref 'c) (ref 'a) (ref 'b)) env))))

  (test-case "infer body type is type of last expression"
    (define env (list (cons 'x i32) (cons 'y f64)))
    (check-equal? (infer-type (body (ref 'x) (ref 'y)) env) f64))

  (test-case "empty body raises"
    (check-exn exn:fail?
               (lambda () (infer-type (body) '()))))

  ;; ---- Function validation --------------------------------------------------

  (test-case "validate well-typed function"
    (define f (func 'add
                (formals (variable 'a i32) (variable 'b i32))
                (body ((op '+) (ref 'a) (ref 'b)))))
    (check-not-exn (lambda () (validate-func f '()))))

  (test-case "validate function with named-bindings"
    (define f (func 'fact
                (formals (variable 'n i32))
                (body
                 (named-bindings 'loop
                   (list (bind (variable 'i i32) (ref 'n))
                         (bind (variable 'acc i32) (lit 1 i32)))
                   (body
                    (if-form ((icmp '<=) (ref 'i) (lit 1 i32))
                             (ref 'acc)
                             (app (ref 'loop)
                                  ((op '-) (ref 'i) (lit 1 i32))
                                  ((op '*) (ref 'acc) (ref 'i)))))))))
    (check-not-exn (lambda () (validate-func f '()))))

  (test-case "validate catches type mismatch in operator"
    (define f (func 'bad
                (formals (variable 'a i32) (variable 'b f64))
                (body ((op '+) (ref 'a) (ref 'b)))))
    (check-exn exn:fail?
               (lambda () (validate-func f '())))))
