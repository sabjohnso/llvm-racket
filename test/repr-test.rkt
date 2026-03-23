#lang racket/base

(module+ test
  (require rackunit
           llvm/private/safe/repr)

  ;; ---- Primitive types -------------------------------------------------------

  (test-case "primitive types are distinct singletons"
    (check-not-false i1)
    (check-not-false i8)
    (check-not-false i16)
    (check-not-false i32)
    (check-not-false i64)
    (check-not-false f32)
    (check-not-false f64)
    (check-not-false void-type)
    (check-not-equal? i32 f32)
    (check-not-equal? i32 i64))

  (test-case "pointer type"
    (define p (ptr-type f64))
    (check-true (ir-type? p))
    (check-equal? (ptr-type-element p) f64))

  (test-case "type-ref for user-defined types"
    (define tr (type-ref 'Point))
    (check-true (ir-type? tr))
    (check-equal? (type-ref-name tr) 'Point))

  ;; ---- Record (struct) types -------------------------------------------------

  (test-case "record type declaration"
    (define point (rec 'Point (field 'x f64) (field 'y f64)))
    (check-true (rec? point))
    (check-equal? (rec-name point) 'Point)
    (check-equal? (length (rec-fields point)) 2)
    (check-equal? (field-name (car (rec-fields point))) 'x)
    (check-equal? (field-type (car (rec-fields point))) f64))

  ;; ---- Tagged union (sum) types ----------------------------------------------

  (test-case "sum type declaration"
    (define opt (sum 'Optional-Float
                  (variant 'Some-Float (field 'value f64))
                  (variant 'No-Float)))
    (check-true (sum? opt))
    (check-equal? (sum-name opt) 'Optional-Float)
    (check-equal? (length (sum-variants opt)) 2)
    (define some (car (sum-variants opt)))
    (check-equal? (variant-name some) 'Some-Float)
    (check-equal? (length (variant-fields some)) 1)
    (define none (cadr (sum-variants opt)))
    (check-equal? (variant-name none) 'No-Float)
    (check-equal? (variant-fields none) '()))

  ;; ---- Expressions -----------------------------------------------------------

  (test-case "literal constants"
    (define c (lit 42 i32))
    (check-true (lit? c))
    (check-equal? (lit-value c) 42)
    (check-equal? (lit-type c) i32))

  (test-case "variable references"
    (define r (ref 'x))
    (check-true (ref? r))
    (check-equal? (ref-name r) 'x))

  (test-case "operator application"
    (define e ((op '+) (ref 'a) (ref 'b)))
    (check-true (op-app? e))
    (check-equal? (op-app-operator e) '+)
    (check-equal? (length (op-app-args e)) 2))

  (test-case "comparison operators"
    (define e ((icmp '<=) (ref 'i) (lit 1 i32)))
    (check-true (icmp-app? e))
    (check-equal? (icmp-app-predicate e) '<=)
    (check-equal? (length (icmp-app-args e)) 2))

  (test-case "floating point comparison"
    (define e ((fcmp '<) (ref 'x) (ref 'y)))
    (check-true (fcmp-app? e))
    (check-equal? (fcmp-app-predicate e) '<))

  (test-case "function application"
    (define e (app (ref 'factorial) (ref 'n)))
    (check-true (app? e))
    (check-equal? (length (app-args e)) 1))

  (test-case "constructor application"
    (define e (ctor 'Some-Float (ref 'x)))
    (check-true (ctor? e))
    (check-equal? (ctor-variant-name e) 'Some-Float)
    (check-equal? (length (ctor-args e)) 1))

  (test-case "if-form"
    (define e (if-form (ref 'cond) (ref 'a) (ref 'b)))
    (check-true (if-form? e))
    (check-not-false (if-form-condition e))
    (check-not-false (if-form-then e))
    (check-not-false (if-form-else e)))

  (test-case "cond-form"
    (define e (cond-form
                (list (cond-clause (ref 'c1) (ref 'a))
                      (cond-clause (ref 'c2) (ref 'b)))
                (ref 'default)))
    (check-true (cond-form? e))
    (check-equal? (length (cond-form-clauses e)) 2)
    (check-not-false (cond-form-else e)))

  (test-case "match-variant"
    (define e (match-variant (ref 'mx)
                (match-case (ctor-pat 'Some-Float (variable 'x f64))
                            (body (ref 'x)))
                (match-case (ctor-pat 'No-Float)
                            (body (lit 0.0 f64)))))
    (check-true (match-variant? e))
    (check-equal? (length (match-variant-cases e)) 2))

  ;; ---- Functions and bindings ------------------------------------------------

  (test-case "variable declaration"
    (define v (variable 'x i32))
    (check-true (variable? v))
    (check-equal? (variable-name v) 'x)
    (check-equal? (variable-type v) i32))

  (test-case "function declaration"
    (define f (func 'add
                (formals (variable 'a i32) (variable 'b i32))
                (body ((op +) (ref 'a) (ref 'b)))))
    (check-true (func? f))
    (check-equal? (func-name f) 'add)
    (check-equal? (length (formals-vars (func-formals f))) 2))

  (test-case "body returns last expression"
    (define b (body (ref 'x) (ref 'y) (ref 'z)))
    (check-true (body? b))
    (check-equal? (length (body-exprs b)) 3))

  (test-case "named-bindings (named let)"
    (define nb (named-bindings 'loop
                 (list (bind (variable 'i i32) (ref 'n))
                       (bind (variable 'acc i32) (lit 1 i32)))
                 (body (ref 'acc))))
    (check-true (named-bindings? nb))
    (check-equal? (named-bindings-name nb) 'loop)
    (check-equal? (length (named-bindings-binds nb)) 2))

  ;; ---- Global values ---------------------------------------------------------

  (test-case "global definition"
    (define g (define-global 'pi f64 (lit 3.14159 f64)))
    (check-true (define-global? g))
    (check-equal? (define-global-name g) 'pi)
    (check-equal? (define-global-type g) f64))

  ;; ---- Full module example from Notes.org ------------------------------------

  (test-case "full module construction matches Notes.org example"
    (define my-module-forms
      (list
       (rec 'Point (field 'x f64) (field 'y f64))
       (func 'my-add (formals (variable 'a i32) (variable 'b i32))
                     (body ((op '+) (ref 'a) (ref 'b))))
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
                                     ((op '*) (ref 'acc) (ref 'i))))))))
       (sum 'Optional-Float
         (variant 'Some-Float (field 'value f64))
         (variant 'No-Float))
       (func 'maybe-sqr (formals (variable 'mx (type-ref 'Optional-Float)))
                        (body
                         (match-variant (ref 'mx)
                           (match-case (ctor-pat 'Some-Float (variable 'x f64))
                                       (body (ctor 'Some-Float ((op '*) (ref 'x) (ref 'x)))))
                           (match-case (ctor-pat 'No-Float)
                                       (body (ctor 'No-Float))))))))

    ;; Should be a list of valid IR forms
    (check-equal? (length my-module-forms) 5)
    (check-true (rec? (list-ref my-module-forms 0)))
    (check-true (func? (list-ref my-module-forms 1)))
    (check-true (func? (list-ref my-module-forms 2)))
    (check-true (sum? (list-ref my-module-forms 3)))
    (check-true (func? (list-ref my-module-forms 4)))))
