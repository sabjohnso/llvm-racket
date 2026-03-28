#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/syntax
           llvm/private/safe/module)

  (test-case "macro: simple add function"
    (define-llvm-module m
      (: add (-> Int32 Int32 Int32))
      (define (add a b) (+ a b)))
    (check-equal? (call m add 3 4) 7))

  (test-case "macro: float multiply"
    (define-llvm-module m
      (: fmul (-> Float64 Float64 Float64))
      (define (fmul x y) (* x y)))
    (check-= (call m fmul 3.0 2.5) 7.5 0.0))

  (test-case "macro: if expression"
    (define-llvm-module m
      (: max (-> Int32 Int32 Int32))
      (define (max a b)
        (if (> a b) a b)))
    (check-equal? (call m max 10 3) 10)
    (check-equal? (call m max 3 10) 10))

  (test-case "macro: named let loop (factorial)"
    (define-llvm-module m
      (: fact (-> Int32 Int32))
      (define (fact n)
        (let loop ([i : Int32 n] [acc : Int32 1])
          (if (<= i 1)
              acc
              (loop (- i 1) (* acc i))))))
    (check-equal? (call m fact 10) 3628800))

  (test-case "macro: multiple functions"
    (define-llvm-module m
      (: double (-> Int32 Int32))
      (define (double x) (+ x x))
      (: quad (-> Int32 Int32))
      (define (quad x) (double (double x))))
    (check-equal? (call m double 5) 10)
    (check-equal? (call m quad 3) 12))

  (test-case "macro: record type"
    (define-llvm-module m
      (define-record Point ([x : Float64] [y : Float64]))
      (: get-x (-> Float64 Float64 Float64))
      (define (get-x a b)
        (Point-x (Point a b))))
    (check-= (call m get-x 3.0 4.0) 3.0 0.0))

  (test-case "macro: union and match"
    (define-llvm-module m
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (: unwrap (-> Int32 Int32))
      (define (unwrap x)
        (match (Some x)
          [(Some v) v]
          [(None) 0])))
    (check-equal? (call m unwrap 42) 42)
    (check-equal? (call m unwrap 0) 0))

  (test-case "macro: match None variant"
    (define-llvm-module m
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (: test-none (-> Int32))
      (define (test-none)
        (match (None)
          [(Some v) 1]
          [(None) 0])))
    (check-equal? (call m test-none) 0))

  (test-case "macro: union with computation in match body"
    (define-llvm-module m
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (: double-or-zero (-> Int32 Int32))
      (define (double-or-zero x)
        (match (Some x)
          [(Some v) (+ v v)]
          [(None) 0])))
    (check-equal? (call m double-or-zero 21) 42))

  (test-case "macro: cond expression"
    (define-llvm-module m
      (: classify (-> Int32 Int32))
      (define (classify x)
        (cond
          [(< x 0)  -1]
          [(= x 0)   0]
          [else       1])))
    (check-equal? (call m classify -5) -1)
    (check-equal? (call m classify 0) 0)
    (check-equal? (call m classify 42) 1))

  (test-case "macro: cond with computation in clauses"
    (define-llvm-module m
      (: abs-val (-> Int32 Int32))
      (define (abs-val x)
        (cond
          [(< x 0) (- 0 x)]
          [else     x])))
    (check-equal? (call m abs-val -7) 7)
    (check-equal? (call m abs-val 5) 5)
    (check-equal? (call m abs-val 0) 0))

  ;; ---- Type inference (inline parameter types, inferred return) ---------------

  (test-case "inferred: simple add"
    (define-llvm-module m
      (define (add [a : Int32] [b : Int32]) (+ a b)))
    (check-equal? (call m add 3 4) 7))

  (test-case "inferred: float multiply"
    (define-llvm-module m
      (define (fmul [x : Float64] [y : Float64]) (* x y)))
    (check-= (call m fmul 3.0 2.5) 7.5 0.0))

  (test-case "inferred: factorial with named let"
    (define-llvm-module m
      (define (fact [n : Int32])
        (let loop ([i : Int32 n] [acc : Int32 1])
          (if (<= i 1) acc (loop (- i 1) (* acc i))))))
    (check-equal? (call m fact 10) 3628800))

  (test-case "inferred: cross-function calls"
    (define-llvm-module m
      (define (double [x : Int32]) (+ x x))
      (define (quad [x : Int32]) (double (double x))))
    (check-equal? (call m quad 3) 12))

  (test-case "inferred: mixed with explicit annotation"
    (define-llvm-module m
      (: add (-> Int32 Int32 Int32))
      (define (add a b) (+ a b))
      (define (inc [x : Int32]) (add x 1)))
    (check-equal? (call m add 3 4) 7)
    (check-equal? (call m inc 9) 10))

  ;; ---- Simple let bindings ---------------------------------------------------

  (test-case "macro: simple let"
    (define-llvm-module m
      (define (dist-sq [ax : Float64] [ay : Float64]
                       [bx : Float64] [by : Float64])
        (let ([dx : Float64 (- ax bx)]
              [dy : Float64 (- ay by)])
          (+ (* dx dx) (* dy dy)))))
    (check-= (call m dist-sq 1.0 2.0 4.0 6.0) 25.0 0.0))

  (test-case "macro: nested let"
    (define-llvm-module m
      (define (f [x : Int32])
        (let ([a : Int32 (+ x 1)])
          (let ([b : Int32 (* a 2)])
            (+ a b)))))
    ;; f(3) = a=4, b=8, 4+8=12
    (check-equal? (call m f 3) 12))

  (test-case "macro: let with single binding"
    (define-llvm-module m
      (define (inc [x : Int32])
        (let ([y : Int32 1])
          (+ x y))))
    (check-equal? (call m inc 9) 10))

  ;; ---- Float cross-function call ------------------------------------------------

  (test-case "standalone : raises helpful error"
    (check-exn
     #rx"can only be used inside define-llvm-module"
     (lambda () (eval '(: sqr (-> Float64 Float64))
                      (module->namespace 'llvm/private/safe/syntax)))))

  (test-case "error: extra parens around params gives clear message"
    ;; User wrote (define (f ([x : T])) ...) with extra parens around params.
    ;; Should get a clear error, not "map: all lists must have same size".
    (check-exn
     #rx"parameter count.*does not match"
     (lambda ()
       (eval '(define-llvm-module m
                (: f (-> Int32 Int32 Int32))
                (define (f (a b)) (+ a b)))
             (module->namespace 'llvm/private/safe/syntax)))))

  (test-case "inferred: float cross-function call in arithmetic"
    ;; Exact scenario from REPL: sqr returns Float64, used in + in another function
    (define-llvm-module m
      (define (sqr [x : Float64]) (* x x))
      (define-record Point ([x : Float64] [y : Float64]))
      (define (distance-sq [p : Point] [q : Point])
        (let ([dx : Float64 (- (Point-x p) (Point-x q))]
              [dy : Float64 (- (Point-y p) (Point-y q))])
          (+ (sqr dx) (sqr dy)))))
    ;; Records are passed as lists of field values
    (check-= (call m distance-sq '(1.0 2.0) '(4.0 6.0)) 25.0 0.0))

  ;; ---- Generated Racket structs for records -----------------------------------

  (test-case "macro: define-record generates Racket struct"
    (define-llvm-module m2
      (define-record Point ([x : Float64] [y : Float64]))
      (define (get-x [p : Point]) (Point-x p)))
    ;; Point struct should exist as a Racket struct
    (define p (Point 3.0 4.0))
    (check-true (Point? p))
    (check-= (Point-x p) 3.0 0.0)
    (check-= (Point-y p) 4.0 0.0))

  (test-case "contract: record rejects wrong field type"
    (define-llvm-module m-ct
      (define-record Pt ([x : Float64] [y : Float64]))
      (define (get-x [p : Pt]) (Pt-x p)))
    (check-exn #rx"expected Float64"
               (lambda () (Pt "hello" 2.0)))
    (check-exn #rx"expected Float64"
               (lambda () (Pt 3.0 42))))

  (test-case "contract: union variant rejects wrong field type"
    (define-llvm-module m-ct2
      (union Opt
        [Just ([value : Int32])]
        [Nothing])
      (define (unwrap [x : Opt]) (match x [(Just v) v] [(Nothing) 0])))
    (check-exn #rx"expected Int32"
               (lambda () (Just "not-an-int"))))

  (test-case "macro: union generates Racket variant structs"
    (define-llvm-module m3
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (: unwrap (-> Int32 Int32))
      (define (unwrap x)
        (match (Some x)
          [(Some v) v]
          [(None) 0])))
    ;; Variant structs should exist
    (check-true (Some? (Some 42)))
    (check-equal? (Some-value (Some 42)) 42)
    (check-true (None? (None))))

  ;; ---- Struct-based marshalling via call --------------------------------------

  (test-case "call: pass record struct instance"
    (define-llvm-module m4
      (define-record Point ([x : Float64] [y : Float64]))
      (define (get-x [p : Point]) (Point-x p)))
    (check-= (call m4 get-x (Point 3.0 4.0)) 3.0 0.0))

  (test-case "call: pass union variant struct instance"
    (define-llvm-module m5
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (define (unwrap [x : Opt-Int])
        (match x
          [(Some v) v]
          [(None) 0])))
    (check-equal? (call m5 unwrap (Some 42)) 42)
    (check-equal? (call m5 unwrap (None)) 0))

  ;; ---- Return value unmarshalling --------------------------------------------

  (test-case "call: function returning record gives Racket struct"
    (define-llvm-module m6
      (define-record Point ([x : Float64] [y : Float64]))
      (define (make-pt [x : Float64] [y : Float64])
        (Point x y)))
    (define result (call m6 make-pt 3.0 4.0))
    (check-true (Point? result))
    (check-= (Point-x result) 3.0 0.0)
    (check-= (Point-y result) 4.0 0.0))

  (test-case "call: function returning union gives variant struct"
    (define-llvm-module m7
      (union Opt-Int
        [Some ([value : Int32])]
        [None])
      (define (wrap [x : Int32])
        (Some x)))
    (define result (call m7 wrap 42))
    (check-true (Some? result))
    (check-equal? (Some-value result) 42)))
