#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/module)

  (test-case "record: construct and access field"
    ;; A function that creates a point and returns its x field
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'get-x (formals (variable 'a f64) (variable 'b f64))
                             (body
                              (field-ref
                               (rec-new 'Point (ref 'a) (ref 'b))
                               'Point 'x)))))
    (check-= (call m 'get-x 3.0 4.0) 3.0 0.0))

  (test-case "record: access second field"
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'get-y (formals (variable 'a f64) (variable 'b f64))
                             (body
                              (field-ref
                               (rec-new 'Point (ref 'a) (ref 'b))
                               'Point 'y)))))
    (check-= (call m 'get-y 3.0 4.0) 4.0 0.0))

  (test-case "record: compute with fields"
    ;; distance-squared(ax, ay, bx, by) = (ax-bx)^2 + (ay-by)^2
    (define m (make-llvm-module
               (rec 'Point (field 'x f64) (field 'y f64))
               (func 'dist-sq (formals (variable 'ax f64) (variable 'ay f64)
                                       (variable 'bx f64) (variable 'by f64))
                              (body
                               (let* ([pa (rec-new 'Point (ref 'ax) (ref 'ay))]
                                      [pb (rec-new 'Point (ref 'bx) (ref 'by))]
                                      [dx ((op '-) (field-ref pa 'Point 'x)
                                                   (field-ref pb 'Point 'x))]
                                      [dy ((op '-) (field-ref pa 'Point 'y)
                                                   (field-ref pb 'Point 'y))])
                                 ((op '+) ((op '*) dx dx) ((op '*) dy dy)))))))
    (check-= (call m 'dist-sq 1.0 2.0 4.0 6.0) 25.0 0.0)))
