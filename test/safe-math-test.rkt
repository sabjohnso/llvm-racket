#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr)

  ;; ---- Step 1: intrinsic-func struct ------------------------------------------

  (test-case "intrinsic-func: construct and access fields"
    (define i (intrinsic-func 'sqrt "llvm.sqrt.f64" (list f64) f64))
    (check-true (intrinsic-func? i))
    (check-equal? (intrinsic-func-name i) 'sqrt)
    (check-equal? (intrinsic-func-llvm-name i) "llvm.sqrt.f64")
    (check-equal? (intrinsic-func-param-types i) (list f64))
    (check-equal? (intrinsic-func-ret-type i) f64))

  (test-case "intrinsic-func: two-arg function"
    (define i (intrinsic-func 'pow "llvm.pow.f64" (list f64 f64) f64))
    (check-equal? (length (intrinsic-func-param-types i)) 2)))

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/library)

  ;; ---- Step 2: llvm-library and math-lib -------------------------------------

  (test-case "llvm-library: construct and access"
    (define lib (llvm-library 'test (list)))
    (check-true (llvm-library? lib))
    (check-equal? (llvm-library-name lib) 'test)
    (check-equal? (llvm-library-decls lib) '()))

  (test-case "math-lib: exists and has correct entries"
    (check-true (llvm-library? math-lib))
    (check-equal? (llvm-library-name math-lib) 'math)
    (define decls (llvm-library-decls math-lib))
    (check-equal? (length decls) 15)
    (check-true (andmap (lambda (d) (or (intrinsic-func? d) (overloaded-intrinsic? d))) decls))
    ;; Spot-check some entries
    (define names (map (lambda (d)
                         (if (intrinsic-func? d) (intrinsic-func-name d)
                             (overloaded-intrinsic-name d))) decls))
    (check-not-false (memq 'sqrt names))
    (check-not-false (memq 'sin names))
    (check-not-false (memq 'pow names))
    (check-not-false (memq 'min names))
    (check-not-false (memq 'max names))))

(module+ test
  (require rackunit
           racket/string
           llvm/private/safe/repr
           llvm/private/safe/library
           llvm/private/safe/compile)

  ;; ---- Step 3: compile-module handles intrinsic-func --------------------------

  (test-case "compile: intrinsic-func + user func calling it"
    (define cm (compile-module
                (list
                 (intrinsic-func 'sqrt "llvm.sqrt.f64" (list f64) f64)
                 (func 'my-sqrt (formals (variable 'x f64))
                       (body (app (ref 'sqrt) (ref 'x)))))))
    (check-true (compiled-module? cm))
    (define ir (compiled-module-ir cm))
    (check-true (string-contains? ir "llvm.sqrt.f64"))
    (check-true (string-contains? ir "my-sqrt"))))

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/library
           llvm/private/safe/module)

  ;; ---- Step 4: #:include on make-llvm-module ----------------------------------

  (test-case "include: sqrt via runtime API"
    (define m (make-llvm-module
               #:include (list math-lib)
               (func 'my-sqrt (formals (variable 'x f64))
                     (body (app (ref 'sqrt) (ref 'x))))))
    (check-= (call m my-sqrt 9.0) 3.0 0.001))

  (test-case "include: hypotenuse via runtime API"
    (define m (make-llvm-module
               #:include (list math-lib)
               (func 'hyp (formals (variable 'x f64) (variable 'y f64))
                     (body (app (ref 'sqrt)
                                ((op '+) ((op '*) (ref 'x) (ref 'x))
                                         ((op '*) (ref 'y) (ref 'y))))))))
    (check-= (call m hyp 3.0 4.0) 5.0 0.001))

  ;; ---- Step 5: all math intrinsics end-to-end --------------------------------

  ;; Helper: build a module with one wrapper function calling the intrinsic
  (define (make-unary-math-module name)
    (make-llvm-module
     #:include (list math-lib)
     (func 'f (formals (variable 'x f64))
           (body (app (ref name) (ref 'x))))))

  (define (make-binary-math-module name)
    (make-llvm-module
     #:include (list math-lib)
     (func 'f (formals (variable 'x f64) (variable 'y f64))
           (body (app (ref name) (ref 'x) (ref 'y))))))

  (test-case "math: sqrt"
    (check-= (call (make-unary-math-module 'sqrt) f 25.0) 5.0 0.001))

  (test-case "math: abs"
    (check-= (call (make-unary-math-module 'abs) f -7.5) 7.5 0.001)
    (check-= (call (make-unary-math-module 'abs) f 3.0) 3.0 0.001))

  (test-case "math: pow"
    (check-= (call (make-binary-math-module 'pow) f 2.0 10.0) 1024.0 0.001))

  (test-case "math: floor"
    (check-= (call (make-unary-math-module 'floor) f 3.7) 3.0 0.001)
    (check-= (call (make-unary-math-module 'floor) f -1.2) -2.0 0.001))

  (test-case "math: ceil"
    (check-= (call (make-unary-math-module 'ceil) f 3.2) 4.0 0.001)
    (check-= (call (make-unary-math-module 'ceil) f -1.8) -1.0 0.001))

  (test-case "math: round"
    (check-= (call (make-unary-math-module 'round) f 3.5) 4.0 0.001)
    (check-= (call (make-unary-math-module 'round) f 2.3) 2.0 0.001))

  (test-case "math: sin"
    (check-= (call (make-unary-math-module 'sin) f 0.0) 0.0 0.001))

  (test-case "math: cos"
    (check-= (call (make-unary-math-module 'cos) f 0.0) 1.0 0.001))

  (test-case "math: exp"
    (check-= (call (make-unary-math-module 'exp) f 0.0) 1.0 0.001)
    (check-= (call (make-unary-math-module 'exp) f 1.0) 2.71828 0.001))

  (test-case "math: log"
    (check-= (call (make-unary-math-module 'log) f 1.0) 0.0 0.001)
    (check-= (call (make-unary-math-module 'log) f 2.71828) 1.0 0.001))

  (test-case "math: log2"
    (check-= (call (make-unary-math-module 'log2) f 8.0) 3.0 0.001))

  (test-case "math: log10"
    (check-= (call (make-unary-math-module 'log10) f 1000.0) 3.0 0.001))

  (test-case "math: min"
    (check-= (call (make-binary-math-module 'min) f 3.0 7.0) 3.0 0.001)
    (check-= (call (make-binary-math-module 'min) f 7.0 3.0) 3.0 0.001))

  (test-case "math: max"
    (check-= (call (make-binary-math-module 'max) f 3.0 7.0) 7.0 0.001)
    (check-= (call (make-binary-math-module 'max) f 7.0 3.0) 7.0 0.001)))

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/library
           llvm/private/safe/syntax
           llvm/private/safe/module)

  ;; ---- Step 6: macro layer (include expr) -------------------------------------

  (test-case "macro: include math-lib and use sqrt"
    (define-llvm-module m
      (include math-lib)
      (define (my-sqrt [x : Float64]) (sqrt x)))
    (check-= (call m my-sqrt 9.0) 3.0 0.001))

  (test-case "macro: include math-lib hypotenuse"
    (define-llvm-module m
      (include math-lib)
      (define (hyp [x : Float64] [y : Float64])
        (sqrt (+ (* x x) (* y y)))))
    (check-= (call m hyp 3.0 4.0) 5.0 0.001))

  (test-case "macro: include math-lib with pow"
    (define-llvm-module m
      (include math-lib)
      (define (cube [x : Float64]) (pow x 3.0)))
    (check-= (call m cube 4.0) 64.0 0.001))

  ;; ---- Step 7: name shadowing ------------------------------------------------

  (test-case "shadowing: user-defined abs overrides library abs"
    (define m (make-llvm-module
               #:include (list math-lib)
               ;; User defines abs as integer absolute value
               (func 'abs (formals (variable 'x i32))
                     (body (if-form ((icmp '<) (ref 'x) (lit 0 i32))
                                   ((op '-) (lit 0 i32) (ref 'x))
                                   (ref 'x))))))
    (check-equal? (call m abs -7) 7)
    (check-equal? (call m abs 5) 5)))
