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
               [type-env '()]      ; ((name param-types ret-type) ...)
               [decls '()]
               [rec-names '()]     ; known record type names
               [variant-names '()] ; known variant constructor names
               [union-names '()])  ; known union type names
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
                    decls rec-names variant-names union-names))])]

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
                    (cons rname rec-names)
                    variant-names union-names))])]

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
                              type-env rec-names variant-names)]
                   [decl #`(func '#,fn-name #,formals-stx (body #,@body-stx))])
              (loop (cdr remaining) type-env
                    (cons decl decls)
                    rec-names variant-names union-names))])]

        ;; Union definition: (union Name [Variant ([field : Type] ...)] ...)
        [(syntax-case (car remaining) (union)
           [(union name clause ...) #t]
           [_ #f])
         (syntax-case (car remaining) (union :)
           [(union name clause ...)
            (let* ([uname (syntax-e #'name)]
                   [clauses (syntax->list #'(clause ...))]
                   [variants
                    (map (lambda (c)
                           (syntax-case c (:)
                             [[vname ([fname : ftype] ...)]
                              (let ([vn (syntax-e #'vname)]
                                    [flds (map (lambda (fn ft)
                                                 #`(field '#,(syntax-e fn)
                                                          #,(type-name->repr ft)))
                                               (syntax->list #'(fname ...))
                                               (syntax->list #'(ftype ...)))])
                                (cons vn #`(variant '#,vn #,@flds)))]
                             [[vname]
                              (cons (syntax-e #'vname)
                                    #`(variant '#,(syntax-e #'vname)))]))
                         clauses)]
                   [new-variant-names (append (map car variants) variant-names)]
                   [decl #`(sum '#,uname #,@(map cdr variants))])
              (loop (cdr remaining) type-env
                    (cons decl decls)
                    rec-names new-variant-names
                    (cons uname union-names)))])]

        [else
         (raise-syntax-error 'define-llvm-module
                             "unexpected form" (car remaining))])))

  ;; Transform a list of body expressions to runtime API calls.
  (define (transform-body exprs type-env rec-names variant-names)
    (map (lambda (e) (transform-expr e type-env rec-names variant-names)) exprs))

  ;; Shorthand for recursive transform.
  (define (tx e te rn vn)
    (transform-expr e te rn vn))
  (define (tx* es te rn vn)
    (map (lambda (e) (tx e te rn vn)) es))

  ;; Transform a single expression.
  (define (transform-expr stx type-env rec-names variant-names)
    (define (tx1 e) (tx e type-env rec-names variant-names))
    (define (tx1* es) (tx* es type-env rec-names variant-names))
    (syntax-case stx (if let match cond else)
      ;; Literal integer
      [val (exact-integer? (syntax-e #'val))
       #`(lit #,(syntax-e #'val) i32)]

      ;; Literal float
      [val (flonum? (syntax-e #'val))
       #`(lit #,(syntax-e #'val) f64)]

      ;; Variable reference (bare identifier)
      [name (identifier? #'name)
       #`(ref '#,(syntax-e #'name))]

      ;; If expression
      [(if c t e)
       #`(if-form #,(tx1 #'c) #,(tx1 #'t) #,(tx1 #'e))]

      ;; Cond expression — expand to nested if-forms
      [(cond clause ...)
       (let ([clauses (syntax->list #'(clause ...))])
         (let expand-cond ([remaining clauses])
           (cond
             [(null? remaining)
              (raise-syntax-error 'define-llvm-module
                                  "cond must have an else clause" stx)]
             ;; [else expr]
             [(syntax-case (car remaining) (else)
                [(else body) #t]
                [_ #f])
              (syntax-case (car remaining) (else)
                [(else body) (tx1 #'body)])]
             ;; [test expr]
             [else
              (syntax-case (car remaining) ()
                [[test body]
                 #`(if-form #,(tx1 #'test)
                            #,(tx1 #'body)
                            #,(expand-cond (cdr remaining)))])])))]

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
                                    #,(tx1 i)))
                          vars types inits)]
              [body-stxs (transform-body bodies type-env rec-names variant-names)])
         #`(named-bindings '#,(syntax-e #'loop-name)
                           (list #,@binds)
                           (body #,@body-stxs)))]

      ;; Match expression: (match expr [(Variant args ...) body ...] ...)
      [(match scrutinee-expr clause ...)
       (let* ([scrut (tx1 #'scrutinee-expr)]
              [cases
               (map (lambda (c)
                      (syntax-case c ()
                        [[(vname pat-args ...) case-body ...]
                         (let* ([vn (syntax-e #'vname)]
                                [pat-bindings
                                 (map (lambda (pa)
                                        ;; Pattern arg is just a variable name.
                                        ;; We need a type — for now use i32 as default.
                                        ;; TODO: look up from variant definition.
                                        #`(variable '#,(syntax-e pa) i32))
                                      (syntax->list #'(pat-args ...)))]
                                [case-bodies
                                 (transform-body (syntax->list #'(case-body ...))
                                                 type-env rec-names variant-names)])
                           #`(match-case (ctor-pat '#,vn #,@pat-bindings)
                                         (body #,@case-bodies)))]
                        [[(vname) case-body ...]
                         (let ([case-bodies
                                (transform-body (syntax->list #'(case-body ...))
                                                type-env rec-names variant-names)])
                           #`(match-case (ctor-pat '#,(syntax-e #'vname))
                                         (body #,@case-bodies)))]))
                    (syntax->list #'(clause ...)))])
         #`(match-variant #,scrut #,@cases))]

      ;; Arithmetic operators
      [(op-id args ...)
       (and (identifier? #'op-id) (op-sym? (syntax-e #'op-id)))
       #`((op '#,(syntax-e #'op-id)) #,@(tx1* (syntax->list #'(args ...))))]

      ;; Comparison operators
      [(cmp-id args ...)
       (and (identifier? #'cmp-id) (cmp-sym? (syntax-e #'cmp-id)))
       #`((icmp '#,(syntax-e #'cmp-id)) #,@(tx1* (syntax->list #'(args ...))))]

      ;; Record constructor: (Point a b)
      [(ctor-name args ...)
       (and (identifier? #'ctor-name)
            (memq (syntax-e #'ctor-name) rec-names))
       #`(rec-new '#,(syntax-e #'ctor-name) #,@(tx1* (syntax->list #'(args ...))))]

      ;; Variant constructor: (Some x) or (None)
      [(vname args ...)
       (and (identifier? #'vname)
            (memq (syntax-e #'vname) variant-names))
       #`(ctor '#,(syntax-e #'vname) #,@(tx1* (syntax->list #'(args ...))))]

      ;; Record field accessor: (Point-x expr)
      [(accessor-id arg)
       (and (identifier? #'accessor-id)
            (let* ([s (symbol->string (syntax-e #'accessor-id))]
                   [parts (regexp-match #rx"^(.+)-(.+)$" s)])
              (and parts
                   (memq (string->symbol (second parts)) rec-names))))
       (let* ([s (symbol->string (syntax-e #'accessor-id))]
              [parts (regexp-match #rx"^(.+)-(.+)$" s)]
              [type-name (string->symbol (second parts))]
              [field-name (string->symbol (third parts))])
         #`(field-ref #,(tx1 #'arg) '#,type-name '#,field-name))]

      ;; Function application: (name args ...)
      [(fn-id args ...)
       (identifier? #'fn-id)
       #`(app (ref '#,(syntax-e #'fn-id)) #,@(tx1* (syntax->list #'(args ...))))]

      [other
       (raise-syntax-error 'define-llvm-module
                           "unsupported expression form"
                           #'other)])))

;; Re-provide runtime API for use in expanded code
(require "repr.rkt" "module.rkt")
(provide (all-from-out "repr.rkt")
         (all-from-out "module.rkt"))
