#lang racket/base

(require (for-syntax racket/base
                     racket/list
                     racket/syntax))

(provide define-llvm-module
         : -> include)

;; Auxiliary syntax keywords — only meaningful inside define-llvm-module.
(define-syntax (: stx)
  (raise-syntax-error ': "can only be used inside define-llvm-module" stx))
(define-syntax (-> stx)
  (raise-syntax-error '-> "can only be used inside define-llvm-module" stx))
(define-syntax (include stx)
  (raise-syntax-error 'include "can only be used inside define-llvm-module" stx))

;; The macro collects type annotations and definitions, then expands
;; to a make-llvm-module call with the runtime API forms.

(define-syntax (define-llvm-module stx)
  (syntax-case stx ()
    [(_ name body ...)
     ;; Process body forms into declarations, includes, struct definitions, and registry
     (let-values ([(decls includes struct-defs reg-entries)
                   (process-module-body (syntax->list #'(body ...)))])
       (with-syntax ([(decl ...) decls]
                     [(lib ...) includes]
                     [(sdef ...) struct-defs]
                     [(reg ...) reg-entries])
         (define has-includes? (not (null? includes)))
         (define has-registry? (not (null? reg-entries)))
         #`(begin
             sdef ...
             (define name
               (make-llvm-module
                #,@(if has-includes? #'(#:include (list lib ...)) #'())
                #,@(if has-registry?
                       #'(#:types (make-immutable-hash (list reg ...)))
                       #'())
                decl ...)))))]))

(begin-for-syntax
  ;; Type name mapping — handles simple names and compound (Vec N Type) form
  (define (type-name->repr type-stx)
    (syntax-case type-stx (Vec)
      [(Vec count elem)
       (exact-positive-integer? (syntax-e #'count))
       #`(vec-type #,(type-name->repr #'elem) #,(syntax-e #'count))]
      [name
       (identifier? #'name)
       (case (syntax-e #'name)
         [(Int1 Bool)   #'i1]
         [(Int8)        #'i8]
         [(Int16)       #'i16]
         [(Int32)       #'i32]
         [(Int64)       #'i64]
         [(Float32)     #'f32]
         [(Float64)     #'f64]
         [(Void)        #'void-type]
         [else          #`(type-ref '#,(syntax-e #'name))])]))

  ;; Map type names to Racket predicates for struct guard contracts.
  ;; Returns (values pred-stx type-label) or (values #f #f) for non-guardable types.
  (define (type-name->guard type-stx)
    (syntax-case type-stx (Vec)
      [(Vec count elem) (values #f #f)]  ; vec-type: no simple predicate
      [name
       (identifier? #'name)
       (case (syntax-e #'name)
         [(Int1 Bool)               (values #'boolean?     "Bool")]
         [(Int8)                    (values #'byte?        "Int8")]
         [(Int16 Int32 Int64)       (values #'exact-integer?
                                            (symbol->string (syntax-e #'name)))]
         [(Float32 Float64)         (values #'flonum?
                                            (symbol->string (syntax-e #'name)))]
         [else                      (values #f #f)])]))

  ;; Generate a #:guard lambda for a struct with typed fields.
  ;; field-names: list of syntax identifiers
  ;; field-type-stxs: list of type syntax (e.g., #'Float64)
  ;; Returns guard syntax or #f if no guards needed.
  (define (make-struct-guard field-names field-type-stxs)
    (define checks
      (for/list ([fn (in-list field-names)]
                 [ft (in-list field-type-stxs)])
        (define-values (pred label) (type-name->guard ft))
        (if pred
            #`(unless (#,pred #,fn)
                (error type-name "~a: expected ~a, got ~e"
                       '#,(syntax-e fn) #,label #,fn))
            #f)))
    (define real-checks (filter values checks))
    (if (null? real-checks)
        #f
        (with-syntax ([(fld ...) field-names]
                      [(chk ...) real-checks])
          #'(lambda (fld ... type-name) chk ... (values fld ...)))))

  ;; Operator mapping
  (define (op-sym? sym)
    (memq sym '(+ - * / mod rem bit-and bit-or bit-xor bit-not shl shr neg)))

  (define (cmp-sym? sym)
    (memq sym '(= != < <= > >=)))

  ;; Helper: check if an identifier has a given symbolic name,
  ;; regardless of its binding (works across modules, REPL, etc.)
  (define (id-name=? stx sym)
    (and (identifier? stx) (eq? (syntax-e stx) sym)))

  ;; Process module body: collect type annotations and definitions.
  ;; Returns four values: (decls, includes, struct-defs, registry-entries).
  (define (process-module-body forms)
    (let loop ([remaining forms]
               [type-env '()]      ; ((name param-types ret-type) ...)
               [decls '()]
               [includes '()]      ; library expressions for #:include
               [struct-defs '()]   ; Racket struct definitions to generate
               [reg-entries '()]   ; type registry entries for marshalling
               [rec-names '()]     ; known record type names
               [rec-field-names '()] ; ((rec-name field-name ...) ...)
               [variant-names '()] ; known variant constructor names
               [union-names '()])  ; known union type names
      (cond
        [(null? remaining)
         (values (reverse decls) (reverse includes)
                 (reverse struct-defs) (reverse reg-entries))]

        ;; Include a library: (include expr)
        [(syntax-case (car remaining) (include)
           [(include _) #t]
           [_ #f])
         (syntax-case (car remaining) (include)
           [(include lib-expr)
            (loop (cdr remaining) type-env decls
                  (cons #'lib-expr includes) struct-defs reg-entries
                  rec-names rec-field-names variant-names union-names)])]

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
                    decls includes struct-defs reg-entries
                    rec-names rec-field-names variant-names union-names))])]

        ;; Record definition: (struct Name ([field : Type] ...))
        [(syntax-case (car remaining) ()
           [(kid name (clause ...)) (id-name=? #'kid 'struct) #t]
           [_ #f])
         (syntax-case (car remaining) (:)
           [(_ name (clause ...))
            (let* ([rname (syntax-e #'name)]
                   [clause-list (syntax->list #'(clause ...))]
                   [field-names (map (lambda (c)
                                       (syntax-case c (:) [[fname : _] #'fname]))
                                     clause-list)]
                   [fields (map (lambda (c)
                                  (syntax-case c (:)
                                    [[fname : ftype]
                                     #`(field '#,(syntax-e #'fname)
                                              #,(type-name->repr #'ftype))]))
                                clause-list)]
                   [decl #`(rec '#,rname #,@fields)]
                   ;; Generate Racket struct definition with type guard
                   [field-type-stxs (map (lambda (c)
                                           (syntax-case c (:) [[_ : ftype] #'ftype]))
                                         clause-list)]
                   [guard (make-struct-guard field-names field-type-stxs)]
                   [sdef (if guard
                             #`(struct name (#,@field-names) #:transparent
                                       #:guard #,guard)
                             #`(struct name (#,@field-names) #:transparent))]
                   ;; Generate registry entry for marshalling
                   [pred-id (format-id #'name "~a?" #'name)]
                   [accessor-ids (map (lambda (fn)
                                        (format-id #'name "~a-~a" #'name fn))
                                      field-names)]
                   [reg #`(cons '#,rname
                                (list 'record name #,pred-id
                                      (list #,@accessor-ids)))])
              (loop (cdr remaining) type-env
                    (cons decl decls) includes
                    (cons sdef struct-defs)
                    (cons reg reg-entries)
                    (cons rname rec-names)
                    (cons (cons rname (map syntax-e field-names)) rec-field-names)
                    variant-names union-names))])]

        ;; Function definition: (define (name args ...) body ...)
        ;; Args can be bare identifiers (requires prior : annotation)
        ;; or typed: [arg : Type]
        [(syntax-case (car remaining) (define)
           [(define (name args ...) body ...) #t]
           [_ #f])
         (syntax-case (car remaining) (define)
           [(define (name args ...) body-expr ...)
            (let* ([fn-name (syntax-e #'name)]
                   [raw-args (syntax->list #'(args ...))]
                   ;; Detect inline typed args: [arg : Type]
                   [has-inline-types?
                    (and (pair? raw-args)
                         (syntax-case (car raw-args) (:)
                           [[_ : _] #t]
                           [_ #f]))]
                   ;; Extract arg names and types
                   [arg-names
                    (if has-inline-types?
                        (map (lambda (a)
                               (syntax-case a (:)
                                 [[n : _] (syntax-e #'n)]))
                             raw-args)
                        (map syntax-e raw-args))]
                   [param-types
                    (if has-inline-types?
                        (map (lambda (a)
                               (syntax-case a (:)
                                 [[_ : t] (type-name->repr #'t)]))
                             raw-args)
                        (let ([type-info (assq fn-name type-env)])
                          (unless type-info
                            (raise-syntax-error 'define-llvm-module
                                                (format "missing type annotation for ~a" fn-name)
                                                (car remaining)))
                          (second type-info)))]
                   [_ (unless (= (length arg-names) (length param-types))
                        (raise-syntax-error
                         'define-llvm-module
                         (format "parameter count for ~a does not match type annotation: ~a parameter~a but ~a type~a"
                                 fn-name
                                 (length arg-names)
                                 (if (= (length arg-names) 1) "" "s")
                                 (length param-types)
                                 (if (= (length param-types) 1) "" "s"))
                         (car remaining)))]
                   [formals-stx
                    #`(formals #,@(map (lambda (n t)
                                         #`(variable '#,n #,t))
                                       arg-names param-types))]
                   [body-stx (transform-body
                              (syntax->list #'(body-expr ...))
                              type-env rec-names variant-names rec-field-names)]
                   [decl #`(func '#,fn-name #,formals-stx (body #,@body-stx))])
              ;; When using inline types, add to type-env so later functions
              ;; can reference this one (even without explicit : annotation).
              ;; Use #f for return type — inferred at runtime.
              (define new-type-env
                (if has-inline-types?
                    (cons (list fn-name param-types #f) type-env)
                    type-env))
              (loop (cdr remaining) new-type-env
                    (cons decl decls) includes struct-defs reg-entries
                    rec-names rec-field-names variant-names union-names))])]

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
                   [decl #`(sum '#,uname #,@(map cdr variants))]
                   ;; Generate Racket struct for each variant (with type guards)
                   [variant-sdefs
                    (map (lambda (c)
                           (syntax-case c (:)
                             [[vname ([fname : ftype] ...)]
                              (let ([guard (make-struct-guard
                                           (syntax->list #'(fname ...))
                                           (syntax->list #'(ftype ...)))])
                                (if guard
                                    #`(struct vname (fname ...) #:transparent
                                              #:guard #,guard)
                                    #`(struct vname (fname ...) #:transparent)))]
                             [[vname]
                              #`(struct vname () #:transparent)]))
                         clauses)]
                   ;; Generate registry entry for union marshalling
                   [variant-reg-entries
                    (map (lambda (c)
                           (syntax-case c (:)
                             [[vname ([fname : ftype] ...)]
                              (let ([vn-sym (syntax-e #'vname)]
                                    [pred (format-id #'vname "~a?" #'vname)]
                                    [accs (map (lambda (fn)
                                                 (format-id #'vname "~a-~a" #'vname fn))
                                               (syntax->list #'(fname ...)))])
                                #`(list '#,vn-sym vname #,pred (list #,@accs)))]
                             [[vname]
                              (let ([vn-sym (syntax-e #'vname)]
                                    [pred (format-id #'vname "~a?" #'vname)])
                                #`(list '#,vn-sym vname #,pred (list)))]))
                         clauses)]
                   [reg #`(cons '#,uname
                                (list 'union (list #,@variant-reg-entries)))])
              (loop (cdr remaining) type-env
                    (cons decl decls) includes
                    (append variant-sdefs struct-defs)
                    (cons reg reg-entries)
                    rec-names rec-field-names new-variant-names
                    (cons uname union-names)))])]

        [else
         (raise-syntax-error 'define-llvm-module
                             "unexpected form" (car remaining))])))

  ;; Transform a list of body expressions to runtime API calls.
  (define (transform-body exprs type-env rec-names variant-names [rfn '()])
    (map (lambda (e) (transform-expr e type-env rec-names variant-names rfn)) exprs))

  ;; Shorthand for recursive transform.
  (define (tx e te rn vn [rfn '()])
    (transform-expr e te rn vn rfn))
  (define (tx* es te rn vn [rfn '()])
    (map (lambda (e) (tx e te rn vn rfn)) es))

  ;; Transform a single expression.
  (define (transform-expr stx type-env rec-names variant-names [rfn '()])
    (define (tx1 e) (tx e type-env rec-names variant-names rfn))
    (define (tx1* es) (tx* es type-env rec-names variant-names rfn))
    (syntax-case stx ()
      ;; Void expression
      [(vid) (id-name=? #'vid 'void) #'(void-expr)]

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
      [(kid c t e) (id-name=? #'kid 'if)
       #`(if-form #,(tx1 #'c) #,(tx1 #'t) #,(tx1 #'e))]

      ;; Cond expression — expand to nested if-forms
      [(kid clause ...) (id-name=? #'kid 'cond)
       (let ([clauses (syntax->list #'(clause ...))])
         (let expand-cond ([remaining clauses])
           (cond
             [(null? remaining)
              (raise-syntax-error 'define-llvm-module
                                  "cond must have an else clause" stx)]
             ;; [else expr]
             [(syntax-case (car remaining) ()
                [(eid body) (id-name=? #'eid 'else) #t]
                [_ #f])
              (syntax-case (car remaining) ()
                [(eid body) (tx1 #'body)])]
             ;; [test expr]
             [else
              (syntax-case (car remaining) ()
                [[test body]
                 #`(if-form #,(tx1 #'test)
                            #,(tx1 #'body)
                            #,(expand-cond (cdr remaining)))])])))]

      ;; Simple let (non-named): (let ([v : T expr] ...) body ...)
      ;; Expand to named-bindings with a fresh unused loop name.
      ;; The body never recurses, so it's just variable bindings.
      [(kid ([var : type init] ...) body-expr ...)
       (and (id-name=? #'kid 'let)
            (not (identifier? (car (syntax->list #'([var : type init] ...))))))
       (let* ([vars (syntax->list #'(var ...))]
              [types (syntax->list #'(type ...))]
              [inits (syntax->list #'(init ...))]
              [bodies (syntax->list #'(body-expr ...))]
              [binds (map (lambda (v t i)
                            #`(bind (variable '#,(syntax-e v)
                                              #,(type-name->repr t))
                                    #,(tx1 i)))
                          vars types inits)]
              [body-stxs (transform-body bodies type-env rec-names variant-names rfn)])
         #`(named-bindings '%let
                           (list #,@binds)
                           (body #,@body-stxs)))]

      ;; Named let
      [(kid loop-name ([var : type init] ...) body-expr ...)
       (and (id-name=? #'kid 'let) (identifier? #'loop-name))
       (let* ([vars (syntax->list #'(var ...))]
              [types (syntax->list #'(type ...))]
              [inits (syntax->list #'(init ...))]
              [bodies (syntax->list #'(body-expr ...))]
              [binds (map (lambda (v t i)
                            #`(bind (variable '#,(syntax-e v)
                                              #,(type-name->repr t))
                                    #,(tx1 i)))
                          vars types inits)]
              [body-stxs (transform-body bodies type-env rec-names variant-names rfn)])
         #`(named-bindings '#,(syntax-e #'loop-name)
                           (list #,@binds)
                           (body #,@body-stxs)))]

      ;; Match expression: (match expr [(Variant args ...) body ...] ...)
      [(kid scrutinee-expr clause ...) (id-name=? #'kid 'match)
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
                                                 type-env rec-names variant-names rfn)])
                           #`(match-case (ctor-pat '#,vn #,@pat-bindings)
                                         (body #,@case-bodies)))]
                        [[(vname) case-body ...]
                         (let ([case-bodies
                                (transform-body (syntax->list #'(case-body ...))
                                                type-env rec-names variant-names rfn)])
                           #`(match-case (ctor-pat '#,(syntax-e #'vname))
                                         (body #,@case-bodies)))]))
                    (syntax->list #'(clause ...)))])
         #`(match-variant #,scrut #,@cases))]

      ;; Arithmetic operators — variadic, desugared to binary left-fold
      [(op-id args ...)
       (and (identifier? #'op-id) (op-sym? (syntax-e #'op-id)))
       (let* ([sym (syntax-e #'op-id)]
              [arg-stxs (syntax->list #'(args ...))]
              [n (length arg-stxs)])
         (cond
           ;; Unary: (+ x) → identity, (- x) → negation, (* x) → identity
           [(= n 1)
            (define tx-arg (tx1 (car arg-stxs)))
            (if (eq? sym '-)
                #`((op 'neg) #,tx-arg)
                tx-arg)]
           ;; Binary: pass through
           [(= n 2)
            #`((op '#,sym) #,@(tx1* arg-stxs))]
           ;; Variadic (3+): left-fold into nested binary ops
           [(> n 2)
            (let loop ([rest (cddr arg-stxs)]
                       [acc #`((op '#,sym) #,(tx1 (car arg-stxs))
                                           #,(tx1 (cadr arg-stxs)))])
              (if (null? rest)
                  acc
                  (loop (cdr rest)
                        #`((op '#,sym) #,acc #,(tx1 (car rest))))))]
           [else
            (raise-syntax-error 'define-llvm-module
                                (format "~a requires at least 1 argument" sym)
                                #'op-id)]))]

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
      ;; Only matches if the record type AND field name are both known.
      [(accessor-id arg)
       (and (identifier? #'accessor-id)
            (let* ([s (symbol->string (syntax-e #'accessor-id))]
                   [parts (regexp-match #rx"^(.+)-(.+)$" s)])
              (and parts
                   (let ([tname (string->symbol (second parts))]
                         [fname (string->symbol (third parts))])
                     (and (memq tname rec-names)
                          (let ([entry (assq tname rfn)])
                            (and entry (memq fname (cdr entry)))))))))
       (let* ([s (symbol->string (syntax-e #'accessor-id))]
              [parts (regexp-match #rx"^(.+)-(.+)$" s)]
              [type-name (string->symbol (second parts))]
              [field-name (string->symbol (third parts))])
         #`(field-ref #,(tx1 #'arg) '#,type-name '#,field-name))]

      ;; Vector literal: (vec e1 e2 ...)
      [(vec-id elems ...)
       (and (identifier? #'vec-id) (eq? (syntax-e #'vec-id) 'vec))
       (let ([elem-stxs (syntax->list #'(elems ...))])
         (when (null? elem-stxs)
           (raise-syntax-error 'define-llvm-module
                               "vec requires at least one element" stx))
         ;; Infer element type from first element
         (define first-e (car elem-stxs))
         (define elem-t
           (cond [(flonum? (syntax-e first-e)) #'f64]
                 [(exact-integer? (syntax-e first-e)) #'i32]
                 [else #'f64]))  ; default to f64 for variable refs
         #`(vec-lit #,elem-t (list #,@(tx1* elem-stxs))))]

      ;; Vector element access: (vec-ref v i)
      [(vr-id vec-expr idx-expr)
       (and (identifier? #'vr-id) (eq? (syntax-e #'vr-id) 'vec-ref))
       #`(vec-extract #,(tx1 #'vec-expr) #,(tx1 #'idx-expr))]

      ;; Vector element update: (vec-set v i val)
      [(vs-id vec-expr idx-expr val-expr)
       (and (identifier? #'vs-id) (eq? (syntax-e #'vs-id) 'vec-set))
       #`(vec-insert #,(tx1 #'vec-expr) #,(tx1 #'idx-expr) #,(tx1 #'val-expr))]

      ;; Vector shuffle: (vec-shuffle v1 v2 i ...)
      [(vsh-id v1-expr v2-expr mask-idx ...)
       (and (identifier? #'vsh-id) (eq? (syntax-e #'vsh-id) 'vec-shuffle))
       #`(vec-shuffle #,(tx1 #'v1-expr) #,(tx1 #'v2-expr)
                      (list #,@(map syntax-e (syntax->list #'(mask-idx ...)))))]

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
