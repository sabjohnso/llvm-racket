#lang racket/base

(provide ;; Type system
         ir-type?
         prim-type? prim-type-tag
         ;; Primitive types
         i1 i8 i16 i32 i64 f32 f64 void-type
         ;; Compound types
         ptr-type ptr-type? ptr-type-element
         type-ref type-ref? type-ref-name
         ;; Record (product) types
         rec rec? rec-name rec-fields
         field field? field-name field-type
         ;; Tagged union (sum) types
         sum sum? sum-name sum-variants
         variant variant? variant-name variant-fields
         ;; Expressions
         lit lit? lit-value lit-type
         ref ref? ref-name
         op op-app? op-app-operator op-app-args
         icmp icmp-app? icmp-app-predicate icmp-app-args
         fcmp fcmp-app? fcmp-app-predicate fcmp-app-args
         app app? app-callee app-args
         rec-new rec-new? rec-new-type-name rec-new-args
         field-ref field-ref? field-ref-expr field-ref-type-name field-ref-field-name
         ctor ctor? ctor-variant-name ctor-args
         void-expr void-expr?
         if-form if-form? if-form-condition if-form-then if-form-else
         cond-form cond-form? cond-form-clauses cond-form-else
         cond-clause cond-clause? cond-clause-test cond-clause-expr
         match-variant match-variant? match-variant-scrutinee match-variant-cases
         match-case match-case? match-case-pattern match-case-body
         ctor-pat ctor-pat? ctor-pat-variant-name ctor-pat-bindings
         ;; Functions and bindings
         func func? func-name func-formals func-body
         formals formals? formals-vars
         variable variable? variable-name variable-type
         body body? body-exprs
         named-bindings named-bindings? named-bindings-name
         named-bindings-binds named-bindings-body
         bind bind? bind-variable bind-init
         ;; Globals
         define-global define-global? define-global-name
         define-global-type define-global-init)

;; ---- Type representations --------------------------------------------------

(struct prim-type (tag) #:transparent)

(define (ir-type? v)
  (or (prim-type? v)
      (ptr-type? v)
      (type-ref? v)))

(define i1        (prim-type 'i1))
(define i8        (prim-type 'i8))
(define i16       (prim-type 'i16))
(define i32       (prim-type 'i32))
(define i64       (prim-type 'i64))
(define f32       (prim-type 'f32))
(define f64       (prim-type 'f64))
(define void-type (prim-type 'void))

(struct ptr-type (element) #:transparent)
(struct type-ref (name) #:transparent)

;; ---- Aggregate type declarations -------------------------------------------
;; Structs use %name as the internal constructor, then we provide a
;; variadic function under the public name.

(struct %rec (name fields) #:transparent)
(struct field (name type) #:transparent)
(struct %sum (name variants) #:transparent)
(struct %variant (name fields) #:transparent)

(define (rec name . fields)     (%rec name fields))
(define (rec? v)                (%rec? v))
(define (rec-name v)            (%rec-name v))
(define (rec-fields v)          (%rec-fields v))

(define (sum name . variants)   (%sum name variants))
(define (sum? v)                (%sum? v))
(define (sum-name v)            (%sum-name v))
(define (sum-variants v)        (%sum-variants v))

(define (variant name . fields) (%variant name fields))
(define (variant? v)            (%variant? v))
(define (variant-name v)        (%variant-name v))
(define (variant-fields v)      (%variant-fields v))

;; ---- Expression representations --------------------------------------------

(struct lit (value type) #:transparent)
(struct ref (name) #:transparent)

(struct op-app (operator args) #:transparent)

(define (op sym)
  (lambda args (op-app sym args)))

(struct icmp-app (predicate args) #:transparent)

(define (icmp pred)
  (lambda args (icmp-app pred args)))

(struct fcmp-app (predicate args) #:transparent)

(define (fcmp pred)
  (lambda args (fcmp-app pred args)))

;; Void expression — used as the last expression in a void-returning function.
(struct %void-expr () #:transparent)
(define (void-expr) (%void-expr))
(define (void-expr? v) (%void-expr? v))

;; Record construction: (rec-new 'Point expr1 expr2)
(struct %rec-new (type-name args) #:transparent)
(define (rec-new type-name . args) (%rec-new type-name args))
(define (rec-new? v)               (%rec-new? v))
(define (rec-new-type-name v)      (%rec-new-type-name v))
(define (rec-new-args v)           (%rec-new-args v))

;; Record field access: (field-ref expr 'Point 'x)
(struct field-ref (expr type-name field-name) #:transparent)

(struct %app (callee args) #:transparent)

(define (app callee . args)  (%app callee args))
(define (app? v)             (%app? v))
(define (app-callee v)       (%app-callee v))
(define (app-args v)         (%app-args v))

(struct %ctor (variant-name args) #:transparent)

(define (ctor variant-name . args) (%ctor variant-name args))
(define (ctor? v)                  (%ctor? v))
(define (ctor-variant-name v)      (%ctor-variant-name v))
(define (ctor-args v)              (%ctor-args v))

;; ---- Control flow ----------------------------------------------------------

(struct if-form (condition then else) #:transparent)

(struct cond-form (clauses else) #:transparent)
(struct cond-clause (test expr) #:transparent)

(struct %match-variant (scrutinee cases) #:transparent)

(define (match-variant scrutinee . cases) (%match-variant scrutinee cases))
(define (match-variant? v)                (%match-variant? v))
(define (match-variant-scrutinee v)       (%match-variant-scrutinee v))
(define (match-variant-cases v)           (%match-variant-cases v))

(struct match-case (pattern body) #:transparent)

(struct %ctor-pat (variant-name bindings) #:transparent)

(define (ctor-pat variant-name . bindings) (%ctor-pat variant-name bindings))
(define (ctor-pat? v)                      (%ctor-pat? v))
(define (ctor-pat-variant-name v)          (%ctor-pat-variant-name v))
(define (ctor-pat-bindings v)              (%ctor-pat-bindings v))

;; ---- Functions and bindings ------------------------------------------------

(struct func (name formals body) #:transparent)

(struct %formals (vars) #:transparent)

(define (formals . vars)  (%formals vars))
(define (formals? v)      (%formals? v))
(define (formals-vars v)  (%formals-vars v))

(struct variable (name type) #:transparent)

(struct %body (exprs) #:transparent)

(define (body . exprs)  (%body exprs))
(define (body? v)       (%body? v))
(define (body-exprs v)  (%body-exprs v))

(struct named-bindings (name binds body) #:transparent)

(struct bind (variable init) #:transparent)

;; ---- Global values ---------------------------------------------------------

(struct define-global (name type init) #:transparent)
