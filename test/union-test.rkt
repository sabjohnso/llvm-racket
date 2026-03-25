#lang racket/base

(module+ test
  (require rackunit
           racket/string
           llvm/private/safe/repr
           llvm/private/safe/module)

  (test-case "tagged union: construct and match single-field variant"
    ;; Optional-Int: Some(i32) | None
    ;; unwrap(x) = match x { Some(v) => v, None => 0 }
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
    ;; We can't easily construct/pass tagged unions through `call` yet
    ;; since marshalling is not implemented. Test that compilation succeeds.
    (check-true (string? (safe-module-ir m)))
    (check-true (string-contains? (safe-module-ir m) "switch")))

  (test-case "tagged union: construct Some variant in a function"
    (define m (make-llvm-module
               (sum 'Opt-Int
                 (variant 'Some (field 'value i32))
                 (variant 'None))
               (func 'wrap (formals (variable 'x i32))
                     (body
                      ;; Construct a Some, then immediately unwrap it
                      ;; This tests ctor + match-variant end-to-end
                      (match-variant (ctor 'Some (ref 'x))
                        (match-case (ctor-pat 'Some (variable 'v i32))
                                    (body (ref 'v)))
                        (match-case (ctor-pat 'None)
                                    (body (lit 0 i32))))))))
    (check-equal? (call m wrap 42) 42)
    (check-equal? (call m wrap 0) 0))

  (test-case "tagged union: construct None variant"
    (define m (make-llvm-module
               (sum 'Opt-Int
                 (variant 'Some (field 'value i32))
                 (variant 'None))
               (func 'make-none (formals)
                     (body
                      (match-variant (ctor 'None)
                        (match-case (ctor-pat 'Some (variable 'v i32))
                                    (body (lit 1 i32)))
                        (match-case (ctor-pat 'None)
                                    (body (lit 0 i32))))))))
    (check-equal? (call m make-none) 0)))
