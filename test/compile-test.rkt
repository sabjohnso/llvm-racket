#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/safe/repr
           llvm/private/safe/compile)

  ;; ---- Simple arithmetic functions -------------------------------------------

  (test-case "compile simple add function"
    (define m (compile-module
               (list
                (func 'add (formals (variable 'a i32) (variable 'b i32))
                           (body ((op '+) (ref 'a) (ref 'b)))))))
    (check-true (string-contains? (compiled-module-ir m) "define"))
    (check-true (string-contains? (compiled-module-ir m) "add")))

  (test-case "compile float multiply"
    (define m (compile-module
               (list
                (func 'fmul (formals (variable 'x f64) (variable 'y f64))
                            (body ((op '*) (ref 'x) (ref 'y)))))))
    (check-true (string-contains? (compiled-module-ir m) "fmul")))

  (test-case "compile function with literal constant"
    (define m (compile-module
               (list
                (func 'inc (formals (variable 'x i32))
                           (body ((op '+) (ref 'x) (lit 1 i32)))))))
    (check-true (string-contains? (compiled-module-ir m) "add")))

  ;; ---- Multi-expression body -------------------------------------------------

  (test-case "body returns last expression"
    (define m (compile-module
               (list
                (func 'last (formals (variable 'a i32) (variable 'b i32))
                            (body ((op '+) (ref 'a) (ref 'b))
                                  ((op '*) (ref 'a) (ref 'b)))))))
    (check-true (string-contains? (compiled-module-ir m) "mul")))

  ;; ---- Control flow ----------------------------------------------------------

  (test-case "compile if-form"
    (define m (compile-module
               (list
                (func 'max (formals (variable 'a i32) (variable 'b i32))
                           (body
                            (if-form ((icmp '>) (ref 'a) (ref 'b))
                                     (ref 'a)
                                     (ref 'b)))))))
    (check-true (string-contains? (compiled-module-ir m) "icmp sgt"))
    (check-true (string-contains? (compiled-module-ir m) "br")))

  ;; ---- Named bindings (loops) ------------------------------------------------

  (test-case "compile named-bindings loop (factorial)"
    (define m (compile-module
               (list
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
                                              ((op '*) (ref 'acc) (ref 'i)))))))))))
    (check-true (string-contains? (compiled-module-ir m) "phi"))
    (check-true (string-contains? (compiled-module-ir m) "br")))

  ;; ---- Function calls --------------------------------------------------------

  (test-case "compile function calling another function"
    (define m (compile-module
               (list
                (func 'double (formals (variable 'x i32))
                              (body ((op '+) (ref 'x) (ref 'x))))
                (func 'quad (formals (variable 'x i32))
                            (body (app (ref 'double)
                                       (app (ref 'double) (ref 'x))))))))
    (check-true (string-contains? (compiled-module-ir m) "call"))
    (check-true (string-contains? (compiled-module-ir m) "@double"))))
