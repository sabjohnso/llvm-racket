#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/module)

  (test-case "marshal: pass record as argument"
    ;; get-x takes a Point, returns the x field
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'get-x (formals (variable 'p (type-ref 'Point)))
                     (body (field-ref (ref 'p) 'Point 'x)))))
    ;; Pass a record as a list of field values
    (check-= (call m get-x '(3.0 4.0)) 3.0 0.0))

  (test-case "marshal: pass record, compute with fields"
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'sum-xy (formals (variable 'p (type-ref 'Point)))
                     (body ((op '+)
                            (field-ref (ref 'p) 'Point 'x)
                            (field-ref (ref 'p) 'Point 'y))))))
    (check-= (call m sum-xy '(3.0 4.0)) 7.0 0.0))

  (test-case "marshal: pass tagged union as argument"
    (define m (make-llvm-module
               (sum 'Opt-Int
                 (variant 'Some (field 'value i32))
                 (variant 'None))
               (func 'unwrap (formals (variable 'x (type-ref 'Opt-Int)))
                     (body
                      (match-variant (ref 'x)
                        (match-case (ctor-pat 'Some (variable 'v i32))
                                    (body (ref 'v)))
                        (match-case (ctor-pat 'None)
                                    (body (lit 0 i32))))))))
    (check-equal? (call m unwrap '(Some 42)) 42)
    (check-equal? (call m unwrap '(None)) 0))

  (test-case "marshal: mixed primitive and record args"
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'scale-x (formals (variable 'p (type-ref 'Point))
                                       (variable 'k f64))
                     (body ((op '*) (field-ref (ref 'p) 'Point 'x) (ref 'k))))))
    (check-= (call m scale-x '(3.0 4.0) 2.0) 6.0 0.0)))
