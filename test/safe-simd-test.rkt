#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr)

  ;; ---- Step 2: vec-type and vector expressions --------------------------------

  (test-case "vec-type: construct and access"
    (define vt (vec-type f64 4))
    (check-true (vec-type? vt))
    (check-equal? (vec-type-element vt) f64)
    (check-equal? (vec-type-count vt) 4))

  (test-case "vec-lit: construct and access"
    (define vl (vec-lit f64 (list (lit 1.0 f64) (lit 2.0 f64))))
    (check-true (vec-lit? vl))
    (check-equal? (vec-lit-element-type vl) f64)
    (check-equal? (length (vec-lit-values vl)) 2))

  (test-case "vec-extract: construct and access"
    (define ve (vec-extract (ref 'v) (lit 0 i32)))
    (check-true (vec-extract? ve))
    (check-true (ref? (vec-extract-vec ve)))
    (check-true (lit? (vec-extract-index ve))))

  (test-case "vec-insert: construct and access"
    (define vi (vec-insert (ref 'v) (lit 0 i32) (lit 1.0 f64)))
    (check-true (vec-insert? vi))
    (check-true (ref? (vec-insert-vec vi))))

  (test-case "vec-shuffle: construct and access"
    (define vs (vec-shuffle (ref 'a) (ref 'b) '(0 2 1 3)))
    (check-true (vec-shuffle? vs))
    (check-equal? (vec-shuffle-mask vs) '(0 2 1 3))))

(module+ test
  (require rackunit
           llvm/private/safe/repr
           llvm/private/safe/type-check)

  ;; ---- Step 3: type checking for vectors --------------------------------------

  (test-case "op-result-type: vector addition"
    (define vt (vec-type f64 4))
    (check-equal? (op-result-type '+ vt vt) vt))

  (test-case "op-result-type: vector multiply"
    (define vt (vec-type i32 8))
    (check-equal? (op-result-type '* vt vt) vt))

  (test-case "op-result-type: mismatched vector sizes error"
    (check-exn exn:fail?
               (lambda () (op-result-type '+ (vec-type f64 4) (vec-type f64 2)))))

  (test-case "op-result-type: scalar vs vector error"
    (check-exn exn:fail?
               (lambda () (op-result-type '+ f64 (vec-type f64 4)))))

  (test-case "infer-type: vec-lit"
    (check-equal? (infer-type (vec-lit f64 (list (lit 1.0 f64) (lit 2.0 f64))) '())
                  (vec-type f64 2)))

  (test-case "infer-type: vec-extract returns element type"
    (define env (list (cons 'v (vec-type f64 4))))
    (check-equal? (infer-type (vec-extract (ref 'v) (lit 0 i32)) env)
                  f64))

  (test-case "infer-type: vec-insert returns vector type"
    (define env (list (cons 'v (vec-type f64 4))))
    (check-equal? (infer-type (vec-insert (ref 'v) (lit 0 i32) (lit 1.0 f64)) env)
                  (vec-type f64 4))))

(module+ test
  (require rackunit
           racket/string
           llvm/private/safe/repr
           llvm/private/safe/compile)

  ;; ---- Step 4: compilation of vector types ------------------------------------

  (test-case "compile: vector addition"
    (define cm (compile-module
                (list
                 (func 'vadd
                       (formals (variable 'a (vec-type f64 4))
                                (variable 'b (vec-type f64 4)))
                       (body ((op '+) (ref 'a) (ref 'b)))))))
    (check-true (compiled-module? cm))
    (define ir (compiled-module-ir cm))
    (check-true (string-contains? ir "<4 x double>"))
    (check-true (string-contains? ir "fadd")))

  (test-case "compile: vec-lit and vec-extract"
    (define cm (compile-module
                (list
                 (func 'first
                       (formals (variable 'x f64) (variable 'y f64))
                       (body
                        (vec-extract
                         (vec-lit f64 (list (ref 'x) (ref 'y)))
                         (lit 0 i32)))))))
    (define ir (compiled-module-ir cm))
    (check-true (string-contains? ir "insertelement"))
    (check-true (string-contains? ir "extractelement"))))

(module+ test
  (require rackunit
           ffi/vector
           llvm/private/safe/repr
           llvm/private/safe/syntax
           llvm/private/safe/module)

  ;; ---- Steps 5 & 6: end-to-end execution ------------------------------------

  (test-case "end-to-end: dot product via internal vectors"
    (define m (make-llvm-module
               (func 'dot4
                     (formals (variable 'a0 f64) (variable 'a1 f64)
                              (variable 'a2 f64) (variable 'a3 f64)
                              (variable 'b0 f64) (variable 'b1 f64)
                              (variable 'b2 f64) (variable 'b3 f64))
                     (body
                      (named-bindings '%let
                        (list
                         (bind (variable 'a (vec-type f64 4))
                               (vec-lit f64 (list (ref 'a0) (ref 'a1)
                                                  (ref 'a2) (ref 'a3))))
                         (bind (variable 'b (vec-type f64 4))
                               (vec-lit f64 (list (ref 'b0) (ref 'b1)
                                                  (ref 'b2) (ref 'b3)))))
                        (body
                         (named-bindings '%let
                           (list
                            (bind (variable 'p (vec-type f64 4))
                                  ((op '*) (ref 'a) (ref 'b))))
                           (body
                            ((op '+)
                             ((op '+) (vec-extract (ref 'p) (lit 0 i32))
                                      (vec-extract (ref 'p) (lit 1 i32)))
                             ((op '+) (vec-extract (ref 'p) (lit 2 i32))
                                      (vec-extract (ref 'p) (lit 3 i32))))))))))))
    ;; 1*5 + 2*6 + 3*7 + 4*8 = 5+12+21+32 = 70
    (check-= (call m dot4 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0) 70.0 0.001))

  ;; ---- Step 7: macro layer ---------------------------------------------------

  (test-case "macro: dot product with vec syntax"
    (define-llvm-module m
      (define (dot4 [a0 : Float64] [a1 : Float64] [a2 : Float64] [a3 : Float64]
                    [b0 : Float64] [b1 : Float64] [b2 : Float64] [b3 : Float64])
        (let ([a : (Vec 4 Float64) (vec a0 a1 a2 a3)]
              [b : (Vec 4 Float64) (vec b0 b1 b2 b3)])
          (let ([p : (Vec 4 Float64) (* a b)])
            (+ (+ (vec-ref p 0) (vec-ref p 1))
               (+ (vec-ref p 2) (vec-ref p 3)))))))
    (check-= (call m dot4 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0) 70.0 0.001))

  ;; ---- Vector marshalling via ffi/vector --------------------------------------

  (test-case "call: pass f64vector, get scalar back"
    (define m (make-llvm-module
               (func 'vsum
                     (formals (variable 'v (vec-type f64 4)))
                     (body
                      ((op '+)
                       ((op '+) (vec-extract (ref 'v) (lit 0 i32))
                                (vec-extract (ref 'v) (lit 1 i32)))
                       ((op '+) (vec-extract (ref 'v) (lit 2 i32))
                                (vec-extract (ref 'v) (lit 3 i32))))))))
    (check-= (call m vsum (f64vector 1.0 2.0 3.0 4.0)) 10.0 0.001))

  (test-case "call: pass two f64vectors, dot product"
    (define m (make-llvm-module
               (func 'dot
                     (formals (variable 'a (vec-type f64 4))
                              (variable 'b (vec-type f64 4)))
                     (body
                      (named-bindings '%let
                        (list (bind (variable 'p (vec-type f64 4))
                                    ((op '*) (ref 'a) (ref 'b))))
                        (body
                         ((op '+)
                          ((op '+) (vec-extract (ref 'p) (lit 0 i32))
                                   (vec-extract (ref 'p) (lit 1 i32)))
                          ((op '+) (vec-extract (ref 'p) (lit 2 i32))
                                   (vec-extract (ref 'p) (lit 3 i32))))))))))
    (check-= (call m dot (f64vector 1.0 2.0 3.0 4.0)
                         (f64vector 5.0 6.0 7.0 8.0))
              70.0 0.001))

  (test-case "vec-type return raises at FFI boundary (no wrapper yet)"
    (check-exn #rx"vector return.*not yet supported"
               (lambda ()
                 (define m (make-llvm-module
                            (func 'bad (formals (variable 'v (vec-type f64 4)))
                                  (body (ref 'v)))))
                 (call m bad 1.0)))))
