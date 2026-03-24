#lang racket/base

(require (for-syntax racket/base
                     racket/list
                     racket/syntax))

(provide define-llvm-module)

;; The macro collects type annotations and definitions, then expands
;; to a make-llvm-module call with the runtime API forms.

(define-syntax (define-llvm-module stx)
  (syntax-case stx ()
    [(_ name body ...)
     ;; Process body forms into declarations
     (let ([decls (process-module-body (syntax->list #'(body ...)))])
       (with-syntax ([(decl ...) decls])
         #'(define name
             (make-llvm-module decl ...))))]))

(begin-for-syntax
  ;; Type name mapping
  (define (type-name->repr type-stx)
    (define name (syntax-e type-stx))
    (case name
      [(Int1 Bool)   #'i1]
      [(Int8)        #'i8]
      [(Int16)       #'i16]
      [(Int32)       #'i32]
      [(Int64)       #'i64]
      [(Float32)     #'f32]
      [(Float64)     #'f64]
      [(Void)        #'void-type]
      [else          #`(type-ref '#,name)]))

  ;; Operator mapping
  (define (op-sym? sym)
    (memq sym '(+ - * / mod rem bit-and bit-or bit-xor bit-not shl shr neg)))

  (define (cmp-sym? sym)
    (memq sym '(= != < <= > >=)))

  ;; Process module body: collect type annotations and definitions.
  ;; Returns a list of syntax objects for make-llvm-module arguments.
  (define (process-module-body forms)
    (let loop ([remaining forms]
               [type-env '()]  ; ((name . (param-types ret-type)) ...)
               [decls '()]
               [rec-names '()])  ; known record type names
      (cond
        [(null? remaining) (reverse decls)]

        ;; Type annotation: (: name (-> Arg ... Ret))
        [(and (syntax-case (car remaining) (:)
                [(: name (-> args ... ret)) #t]
                [_ #f]))
         (syntax-case (car remaining) (: ->)
           [(: name (-> args ... ret))
            (let* ([param-types (map type-name->repr (syntax->list #'(args ...)))]
                   [ret-type (type-name->repr #'ret)]
                   [fn-name (syntax-e #'name)])
              (loop (cdr remaining)
                    (cons (list fn-name param-types ret-type) type-env)
                    decls
                    rec-names))])]

        ;; Record definition: (define-record Name ([field : Type] ...))
        [(syntax-case (car remaining) (define-record)
           [(define-record name (clause ...)) #t]
           [_ #f])
         (syntax-case (car remaining) (define-record :)
           [(define-record name (clause ...))
            (let* ([rname (syntax-e #'name)]
                   [fields (map (lambda (c)
                                  (syntax-case c (:)
                                    [[fname : ftype]
                                     #`(field '#,(syntax-e #'fname)
                                              #,(type-name->repr #'ftype))]))
                                (syntax->list #'(clause ...)))]
                   [decl #`(rec '#,rname #,@fields)])
              (loop (cdr remaining) type-env
                    (cons decl decls)
                    (cons rname rec-names)))])]

        ;; Function definition: (define (name args ...) body ...)
        [(syntax-case (car remaining) (define)
           [(define (name args ...) body ...) #t]
           [_ #f])
         (syntax-case (car remaining) (define)
           [(define (name args ...) body-expr ...)
            (let* ([fn-name (syntax-e #'name)]
                   [type-info (assq fn-name type-env)]
                   [_ (unless type-info
                        (raise-syntax-error 'define-llvm-module
                                            (format "missing type annotation for ~a" fn-name)
                                            (car remaining)))]
                   [param-types (second type-info)]
                   [arg-names (map syntax-e (syntax->list #'(args ...)))]
                   [formals-stx
                    #`(formals #,@(map (lambda (n t)
                                         #`(variable '#,n #,t))
                                       arg-names param-types))]
                   [body-stx (transform-body
                              (syntax->list #'(body-expr ...))
                              type-env rec-names)]
                   [decl #`(func '#,fn-name #,formals-stx (body #,@body-stx))])
              (loop (cdr remaining) type-env
                    (cons decl decls)
                    rec-names))])]

        [else
         (raise-syntax-error 'define-llvm-module
                             "unexpected form" (car remaining))])))

  ;; Transform a list of body expressions to runtime API calls.
  (define (transform-body exprs type-env rec-names)
    (map (lambda (e) (transform-expr e type-env rec-names)) exprs))

  ;; Transform a single expression.
  (define (transform-expr stx type-env rec-names)
    (syntax-case stx (if let)
      ;; Literal integer
      [val
       (exact-integer? (syntax-e #'val))
       #`(lit #,(syntax-e #'val) i32)]

      ;; Literal float
      [val
       (flonum? (syntax-e #'val))
       #`(lit #,(syntax-e #'val) f64)]

      ;; Variable reference (symbol)
      [name
       (identifier? #'name)
       (let ([sym (syntax-e #'name)])
         ;; Check if it's a known function — if so, it's a ref
         ;; Check if it's a record constructor or field accessor
         (cond
           [(assq sym type-env) #`(ref '#,sym)]
           [(memq sym rec-names) #`(ref '#,sym)]  ; shouldn't happen
           [else #`(ref '#,sym)]))]

      ;; If expression
      [(if cond-expr then-expr else-expr)
       (let ([cond-stx (transform-expr #'cond-expr type-env rec-names)]
             [then-stx (transform-expr #'then-expr type-env rec-names)]
             [else-stx (transform-expr #'else-expr type-env rec-names)])
         #`(if-form #,cond-stx #,then-stx #,else-stx))]

      ;; Named let
      [(let loop-name ([var : type init] ...) body-expr ...)
       (identifier? #'loop-name)
       (let* ([vars (syntax->list #'(var ...))]
              [types (syntax->list #'(type ...))]
              [inits (syntax->list #'(init ...))]
              [bodies (syntax->list #'(body-expr ...))]
              [binds (map (lambda (v t i)
                            #`(bind (variable '#,(syntax-e v)
                                              #,(type-name->repr t))
                                    #,(transform-expr i type-env rec-names)))
                          vars types inits)]
              [body-stxs (transform-body bodies type-env rec-names)])
         #`(named-bindings '#,(syntax-e #'loop-name)
                           (list #,@binds)
                           (body #,@body-stxs)))]

      ;; Arithmetic operators: (+ a b), (- a b), (* a b), (/ a b)
      [(op-id args ...)
       (and (identifier? #'op-id) (op-sym? (syntax-e #'op-id)))
       (let ([sym (syntax-e #'op-id)]
             [arg-stxs (map (lambda (a) (transform-expr a type-env rec-names))
                            (syntax->list #'(args ...)))])
         #`((op '#,sym) #,@arg-stxs))]

      ;; Comparison operators: (<= a b), (> a b), etc.
      [(cmp-id args ...)
       (and (identifier? #'cmp-id) (cmp-sym? (syntax-e #'cmp-id)))
       (let ([sym (syntax-e #'cmp-id)]
             [arg-stxs (map (lambda (a) (transform-expr a type-env rec-names))
                            (syntax->list #'(args ...)))])
         ;; Use icmp for now — we'd need type info to dispatch fcmp
         #`((icmp '#,sym) #,@arg-stxs))]

      ;; Record constructor: (Point a b) where Point is a known record name
      [(ctor-name args ...)
       (and (identifier? #'ctor-name)
            (memq (syntax-e #'ctor-name) rec-names))
       (let ([arg-stxs (map (lambda (a) (transform-expr a type-env rec-names))
                            (syntax->list #'(args ...)))])
         #`(rec-new '#,(syntax-e #'ctor-name) #,@arg-stxs))]

      ;; Record field accessor: (Point-x expr) where Point is known
      [(accessor-id arg)
       (and (identifier? #'accessor-id)
            (let* ([s (symbol->string (syntax-e #'accessor-id))]
                   [parts (regexp-match #rx"^(.+)-(.+)$" s)])
              (and parts
                   (memq (string->symbol (second parts)) rec-names))))
       (let* ([s (symbol->string (syntax-e #'accessor-id))]
              [parts (regexp-match #rx"^(.+)-(.+)$" s)]
              [type-name (string->symbol (second parts))]
              [field-name (string->symbol (third parts))]
              [arg-stx (transform-expr #'arg type-env rec-names)])
         #`(field-ref #,arg-stx '#,type-name '#,field-name))]

      ;; Function application: (name args ...)
      [(fn-id args ...)
       (identifier? #'fn-id)
       (let ([arg-stxs (map (lambda (a) (transform-expr a type-env rec-names))
                            (syntax->list #'(args ...)))])
         #`(app (ref '#,(syntax-e #'fn-id)) #,@arg-stxs))]

      [other
       (raise-syntax-error 'define-llvm-module
                           "unsupported expression form"
                           #'other)])))

;; Re-provide runtime API for use in expanded code
(require "repr.rkt" "module.rkt")
(provide (all-from-out "repr.rkt")
         (all-from-out "module.rkt"))
