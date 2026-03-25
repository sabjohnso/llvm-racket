#lang racket/base

(require "repr.rkt")

(provide op-result-type
         icmp-result-type
         fcmp-result-type
         infer-type
         validate-func
         loop-recur-type
         loop-recur-type?)

;; ---- Loop recurrence sentinel -----------------------------------------------
;; When a loop body recurses, we don't know the return type yet.
;; This sentinel is compatible with any type in if-form branch checking.

(struct loop-recur-type () #:transparent)
(define loop-recur (loop-recur-type))

;; ---- Type predicates -------------------------------------------------------

(define (integer-type? t)
  (and (prim-type? t)
       (memq (prim-type-tag t) '(i1 i8 i16 i32 i64))))

(define (float-type? t)
  (and (prim-type? t)
       (memq (prim-type-tag t) '(f32 f64))))

(define (numeric-type? t)
  (or (integer-type? t) (float-type? t)))

;; ---- Operator registry -----------------------------------------------------

;; Binary arithmetic: both operands must have the same numeric type.
;; Result is the same type.
(define binary-arith-ops '(+ - * / mod rem))

;; Unary arithmetic: one operand, same type back.
(define unary-arith-ops '(neg))

;; Bitwise: both operands must be the same integer type.
(define binary-bitwise-ops '(bit-and bit-or bit-xor shl shr))
(define unary-bitwise-ops '(bit-not))

(define (op-result-type op-sym . arg-types)
  (cond
    ;; Binary arithmetic
    [(and (memq op-sym binary-arith-ops)
          (= (length arg-types) 2))
     (define t1 (car arg-types))
     (define t2 (cadr arg-types))
     (unless (and (numeric-type? t1) (equal? t1 t2))
       (error 'op-result-type
              "operator '~a requires matching numeric types, got ~a and ~a"
              op-sym t1 t2))
     t1]
    ;; Unary arithmetic
    [(and (memq op-sym unary-arith-ops)
          (= (length arg-types) 1))
     (define t (car arg-types))
     (unless (numeric-type? t)
       (error 'op-result-type
              "operator '~a requires a numeric type, got ~a" op-sym t))
     t]
    ;; Binary bitwise
    [(and (memq op-sym binary-bitwise-ops)
          (= (length arg-types) 2))
     (define t1 (car arg-types))
     (define t2 (cadr arg-types))
     (unless (and (integer-type? t1) (equal? t1 t2))
       (error 'op-result-type
              "operator '~a requires matching integer types, got ~a and ~a"
              op-sym t1 t2))
     t1]
    ;; Unary bitwise
    [(and (memq op-sym unary-bitwise-ops)
          (= (length arg-types) 1))
     (define t (car arg-types))
     (unless (integer-type? t)
       (error 'op-result-type
              "operator '~a requires an integer type, got ~a" op-sym t))
     t]
    [else
     (error 'op-result-type
            "unknown operator '~a with ~a arguments" op-sym (length arg-types))]))

;; Integer comparison: both operands same integer type, returns i1.
(define (icmp-result-type pred . arg-types)
  (define t1 (car arg-types))
  (define t2 (cadr arg-types))
  (unless (and (integer-type? t1) (equal? t1 t2))
    (error 'icmp-result-type
           "icmp '~a requires matching integer types, got ~a and ~a"
           pred t1 t2))
  i1)

;; Float comparison: both operands same float type, returns i1.
(define (fcmp-result-type pred . arg-types)
  (define t1 (car arg-types))
  (define t2 (cadr arg-types))
  (unless (and (float-type? t1) (equal? t1 t2))
    (error 'fcmp-result-type
           "fcmp '~a requires matching float types, got ~a and ~a"
           pred t1 t2))
  i1)

;; ---- Type environment ------------------------------------------------------

;; An environment is an alist: ((name . type) ...)
(define (env-lookup name env)
  (cond
    [(assq name env) => cdr]
    [else (error 'type-check "unbound variable: ~a" name)]))

(define (env-extend env name type)
  (cons (cons name type) env))

(define (env-extend* env names types)
  (for/fold ([e env]) ([n (in-list names)] [t (in-list types)])
    (env-extend e n t)))

;; ---- Type inference --------------------------------------------------------

;; func-env: alist of (func-name . (list param-types return-type))
;; for resolving function calls.

(define (infer-type expr env [func-env '()])
  (cond
    [(lit? expr)
     (lit-type expr)]

    [(ref? expr)
     (env-lookup (ref-name expr) env)]

    [(op-app? expr)
     (define arg-types
       (for/list ([a (in-list (op-app-args expr))])
         (infer-type a env func-env)))
     (apply op-result-type (op-app-operator expr) arg-types)]

    [(icmp-app? expr)
     (define arg-types
       (for/list ([a (in-list (icmp-app-args expr))])
         (infer-type a env func-env)))
     (apply icmp-result-type (icmp-app-predicate expr) arg-types)]

    [(fcmp-app? expr)
     (define arg-types
       (for/list ([a (in-list (fcmp-app-args expr))])
         (infer-type a env func-env)))
     (apply fcmp-result-type (fcmp-app-predicate expr) arg-types)]

    [(if-form? expr)
     (define cond-type (infer-type (if-form-condition expr) env func-env))
     (unless (equal? cond-type i1)
       (error 'type-check "if condition must be i1, got ~a" cond-type))
     (define then-type (infer-type (if-form-then expr) env func-env))
     (define else-type (infer-type (if-form-else expr) env func-env))
     ;; loop-recur is compatible with any type (the other branch determines it)
     (cond
       [(loop-recur-type? then-type) else-type]
       [(loop-recur-type? else-type) then-type]
       [(equal? then-type else-type) then-type]
       [else (error 'type-check
                    "if branches must have same type, got ~a and ~a"
                    then-type else-type)])]

    [(void-expr? expr)
     void-type]

    [(rec-new? expr)
     (type-ref (rec-new-type-name expr))]

    [(field-ref? expr)
     ;; Trust the declared type — validated during compilation.
     f64]  ; placeholder

    [(ctor? expr)
     ;; Tagged union constructor — returns the union's type.
     ;; We'd need a type registry to know which sum type this variant
     ;; belongs to. For now, return a generic type-ref.
     (type-ref (ctor-variant-name expr))]

    [(match-variant? expr)
     ;; Infer from the first case's body.
     (define cases (match-variant-cases expr))
     (when (null? cases)
       (error 'type-check "match-variant must have at least one case"))
     (define first-case (car cases))
     ;; Extend env with pattern bindings, then infer body.
     (define bindings (ctor-pat-bindings (match-case-pattern first-case)))
     (define ext-env
       (for/fold ([e env]) ([v (in-list bindings)])
         (env-extend e (variable-name v) (variable-type v))))
     (infer-type (match-case-body first-case) ext-env func-env)]

    [(body? expr)
     (define exprs (body-exprs expr))
     (when (null? exprs)
       (error 'type-check "body must have at least one expression"))
     (define last-type void-type)
     (for ([e (in-list exprs)])
       (set! last-type (infer-type e env func-env)))
     last-type]

    [(named-bindings? expr)
     ;; Infer types of initial bind values, extend env, then check body.
     ;; The loop name is bound as a "function" that can be app'd.
     (define binds (named-bindings-binds expr))
     (define bind-types
       (for/list ([b (in-list binds)])
         (infer-type (bind-init b) env func-env)))
     ;; Extend env with loop variables
     (define loop-env
       (env-extend*
        env
        (map (lambda (b) (variable-name (bind-variable b))) binds)
        (map (lambda (b) (variable-type (bind-variable b))) binds)))
     ;; The loop name resolves to a "function" with the bind variable types.
     ;; We put it in the func-env so app can resolve it.
     (define loop-name (named-bindings-name expr))
     (define loop-func-env
       (cons (cons loop-name
                   (list (map (lambda (b) (variable-type (bind-variable b))) binds)
                         #f))  ; return type unknown until body is checked
             func-env))
     (infer-type (named-bindings-body expr) loop-env loop-func-env)]

    [(app? expr)
     ;; Function or loop application.
     ;; For now, look up in func-env. If the callee is a ref, resolve by name.
     (define callee (app-callee expr))
     (cond
       [(ref? callee)
        (define name (ref-name callee))
        (define entry (assq name func-env))
        (if entry
            ;; Loop call — return type is determined by the loop body.
            ;; For now, we trust it (the body determines the type).
            ;; A proper implementation would unify, but for validation
            ;; we check arg count and types.
            (let* ([info (cdr entry)]
                   [param-types (car info)]
                   [arg-types (for/list ([a (in-list (app-args expr))])
                                (infer-type a env func-env))])
              (unless (= (length arg-types) (length param-types))
                (error 'type-check
                       "~a expects ~a args, got ~a"
                       name (length param-types) (length arg-types)))
              (for ([at (in-list arg-types)]
                    [pt (in-list param-types)])
                (unless (equal? at pt)
                  (error 'type-check
                         "~a argument type mismatch: expected ~a, got ~a"
                         name pt at)))
              ;; For function calls with known return type, use it.
              ;; For loop calls (ret-type = #f), return loop-recur sentinel.
              (define ret-type (cadr info))
              (or ret-type loop-recur))
            ;; Not in func-env — could be a module-level function.
            ;; For now, error.
            (error 'type-check "unknown function: ~a" name))]
       [else
        (error 'type-check "callee must be a ref, got ~a" callee)])]

    [else
     (error 'type-check "unknown expression form: ~a" expr)]))

;; ---- Function validation ---------------------------------------------------

;; Validate a function declaration.  func-env is an alist of
;; (name . (param-types return-type)) for other functions in the module.
(define (validate-func f func-env)
  (define params (formals-vars (func-formals f)))
  (define env
    (for/fold ([e '()]) ([p (in-list params)])
      (env-extend e (variable-name p) (variable-type p))))
  ;; Add self to func-env for recursive calls
  (define self-entry
    (cons (func-name f)
          (list (map variable-type params) #f)))
  (define full-func-env (cons self-entry func-env))
  (infer-type (func-body f) env full-func-env))
