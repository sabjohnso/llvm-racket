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
  (or (integer-type? t)
      (float-type? t)
      (and (vec-type? t) (numeric-type? (vec-type-element t)))))

;; Coerce a literal expression's type to match a target type.
;; Integer literals can be widened to any integer or float type.
;; Float literals can be widened to any float type.
;; Returns the coerced type, or #f if coercion is not possible.
(define (coerce-lit-type expr target-type)
  (and (lit? expr)
       (let ([lt (lit-type expr)])
         (cond
           ;; Int literal → any integer type
           [(and (integer-type? lt) (integer-type? target-type)) target-type]
           ;; Int literal → any float type
           [(and (integer-type? lt) (float-type? target-type)) target-type]
           ;; Float literal → any float type
           [(and (float-type? lt) (float-type? target-type)) target-type]
           ;; Vec of coercible elements
           [(and (vec-type? lt) (vec-type? target-type)
                 (= (vec-type-count lt) (vec-type-count target-type))
                 (coerce-lit-type (lit 0 (vec-type-element lt))
                                  (vec-type-element target-type)))
            target-type]
           [else #f]))))

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
     ;; loop-recur is compatible with any type (self-recursive calls)
     (cond
       [(and (loop-recur-type? t1) (loop-recur-type? t2)) loop-recur]
       [(loop-recur-type? t1) t2]
       [(loop-recur-type? t2) t1]
       [else
        (unless (and (numeric-type? t1) (equal? t1 t2))
          (error 'op-result-type
                 "operator '~a requires matching numeric types, got ~a and ~a"
                 op-sym t1 t2))
        t1])]
    ;; Unary arithmetic
    [(and (memq op-sym unary-arith-ops)
          (= (length arg-types) 1))
     (define t (car arg-types))
     (when (and (not (numeric-type? t)) (not (loop-recur-type? t)))
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

(define (infer-type expr env [func-env '()] [rec-env (hash)] [variant->sum (hash)])
  (cond
    [(lit? expr)
     (lit-type expr)]

    [(ref? expr)
     (env-lookup (ref-name expr) env)]

    [(op-app? expr)
     (define args (op-app-args expr))
     (define raw-types
       (for/list ([a (in-list args)])
         (infer-type a env func-env rec-env variant->sum)))
     ;; Coerce literal types: for binary ops, if types differ and one is a
     ;; literal, promote the literal to match the other operand's type.
     (define arg-types
       (if (= (length args) 2)
           (let ([t1 (car raw-types)] [t2 (cadr raw-types)]
                 [e1 (car args)] [e2 (cadr args)])
             (cond
               [(equal? t1 t2) raw-types]
               [(coerce-lit-type e1 t2) (list t2 t2)]
               [(coerce-lit-type e2 t1) (list t1 t1)]
               [else raw-types]))
           raw-types))
     (apply op-result-type (op-app-operator expr) arg-types)]

    [(icmp-app? expr)
     (define args (icmp-app-args expr))
     (define raw-types
       (for/list ([a (in-list args)])
         (infer-type a env func-env rec-env variant->sum)))
     (define arg-types
       (if (= (length args) 2)
           (let ([t1 (car raw-types)] [t2 (cadr raw-types)]
                 [e1 (car args)] [e2 (cadr args)])
             (cond
               [(equal? t1 t2) raw-types]
               [(coerce-lit-type e1 t2) (list t2 t2)]
               [(coerce-lit-type e2 t1) (list t1 t1)]
               [else raw-types]))
           raw-types))
     (apply icmp-result-type (icmp-app-predicate expr) arg-types)]

    [(fcmp-app? expr)
     (define args (fcmp-app-args expr))
     (define raw-types
       (for/list ([a (in-list args)])
         (infer-type a env func-env rec-env variant->sum)))
     (define arg-types
       (if (= (length args) 2)
           (let ([t1 (car raw-types)] [t2 (cadr raw-types)]
                 [e1 (car args)] [e2 (cadr args)])
             (cond
               [(equal? t1 t2) raw-types]
               [(coerce-lit-type e1 t2) (list t2 t2)]
               [(coerce-lit-type e2 t1) (list t1 t1)]
               [else raw-types]))
           raw-types))
     (apply fcmp-result-type (fcmp-app-predicate expr) arg-types)]

    [(if-form? expr)
     (define cond-type (infer-type (if-form-condition expr) env func-env rec-env variant->sum))
     (unless (equal? cond-type i1)
       (error 'type-check "if condition must be i1, got ~a" cond-type))
     (define then-type (infer-type (if-form-then expr) env func-env rec-env variant->sum))
     (define else-type (infer-type (if-form-else expr) env func-env rec-env variant->sum))
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
     (define key (cons (field-ref-type-name expr) (field-ref-field-name expr)))
     (hash-ref rec-env key
               (lambda () (error 'type-check "unknown field ~a.~a"
                                 (field-ref-type-name expr)
                                 (field-ref-field-name expr))))]

    [(ctor? expr)
     ;; Tagged union constructor — returns the parent sum type.
     (define vname (ctor-variant-name expr))
     (define sum-name (hash-ref variant->sum vname #f))
     (type-ref (or sum-name vname))]

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
     (infer-type (match-case-body first-case) ext-env func-env rec-env variant->sum)]

    [(body? expr)
     (define exprs (body-exprs expr))
     (when (null? exprs)
       (error 'type-check "body must have at least one expression"))
     (define last-type void-type)
     (for ([e (in-list exprs)])
       (set! last-type (infer-type e env func-env rec-env variant->sum)))
     last-type]

    [(named-bindings? expr)
     ;; Infer types of initial bind values, extend env, then check body.
     ;; The loop name is bound as a "function" that can be app'd.
     (define binds (named-bindings-binds expr))
     (define bind-types
       (for/list ([b (in-list binds)])
         (infer-type (bind-init b) env func-env rec-env variant->sum)))
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
     (infer-type (named-bindings-body expr) loop-env loop-func-env rec-env variant->sum)]

    [(app? expr)
     ;; Function or loop application.
     ;; For now, look up in func-env. If the callee is a ref, resolve by name.
     (define callee (app-callee expr))
     (cond
       [(ref? callee)
        (define name (ref-name callee))
        (define entry (assq name func-env))
        (if entry
            (let* ([info (cdr entry)]
                   [arg-types (for/list ([a (in-list (app-args expr))])
                                (infer-type a env func-env rec-env variant->sum))])
              (cond
                ;; Overloaded intrinsic: all args same type, return type = arg type
                [(eq? (car info) 'overloaded)
                 (define arity (cadr info))
                 (unless (= (length arg-types) arity)
                   (error 'type-check
                          "~a expects ~a args, got ~a"
                          name arity (length arg-types)))
                 (car arg-types)]
                ;; Normal function/loop call
                [else
                 (define param-types (car info))
                 (unless (= (length arg-types) (length param-types))
                   (error 'type-check
                          "~a expects ~a args, got ~a"
                          name (length param-types) (length arg-types)))
                 (for ([at (in-list arg-types)]
                       [pt (in-list param-types)]
                       [a  (in-list (app-args expr))])
                   (unless (or (equal? at pt)
                               (coerce-lit-type a pt))
                     (error 'type-check
                            "~a argument type mismatch: expected ~a, got ~a"
                            name pt at)))
                 ;; For function calls with known return type, use it.
                 ;; For loop calls (ret-type = #f), return loop-recur sentinel.
                 (define ret-type (cadr info))
                 (or ret-type loop-recur)]))
            ;; Not in func-env — could be a module-level function.
            ;; For now, error.
            (error 'type-check "unknown function: ~a" name))]
       [else
        (error 'type-check "callee must be a ref, got ~a" callee)])]

    [(vec-lit? expr)
     (vec-type (vec-lit-element-type expr) (length (vec-lit-values expr)))]

    [(vec-extract? expr)
     (define vt (infer-type (vec-extract-vec expr) env func-env rec-env variant->sum))
     (unless (vec-type? vt)
       (error 'type-check "vec-extract requires a vector, got ~a" vt))
     (vec-type-element vt)]

    [(vec-insert? expr)
     (define vt (infer-type (vec-insert-vec expr) env func-env rec-env variant->sum))
     (unless (vec-type? vt)
       (error 'type-check "vec-insert requires a vector, got ~a" vt))
     vt]

    [(vec-shuffle? expr)
     (define vt (infer-type (vec-shuffle-v1 expr) env func-env rec-env variant->sum))
     (unless (vec-type? vt)
       (error 'type-check "vec-shuffle requires vectors, got ~a" vt))
     (vec-type (vec-type-element vt) (length (vec-shuffle-mask expr)))]

    [else
     (error 'type-check "unknown expression form: ~a" expr)]))

;; ---- Function validation ---------------------------------------------------

;; Validate a function declaration.  func-env is an alist of
;; (name . (param-types return-type)) for other functions in the module.
(define (validate-func f func-env [rec-env (hash)] [variant->sum (hash)])
  (define params (formals-vars (func-formals f)))
  (define env
    (for/fold ([e '()]) ([p (in-list params)])
      (env-extend e (variable-name p) (variable-type p))))
  ;; Add self to func-env for recursive calls.
  ;; Preserve any existing return type from the env (from prior iteration passes)
  ;; so self-recursive calls can resolve.
  (define existing (assq (func-name f) func-env))
  (define existing-ret (and existing (cadr (cdr existing))))
  (define self-entry
    (cons (func-name f)
          (list (map variable-type params) existing-ret)))
  (define full-func-env (cons self-entry func-env))
  (infer-type (func-body f) env full-func-env rec-env variant->sum))
