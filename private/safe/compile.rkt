#lang racket/base

(require racket/list
         ffi/unsafe
         "repr.rkt"
         "type-check.rkt"
         "../ffi/lib.rkt"
         "../ffi/types.rkt"
         "../ffi/enums.rkt"
         "../ffi/core.rkt"
         "../ffi/analysis.rkt"
         "../ffi/target.rkt")

(provide compile-module
         compiled-module?
         compiled-module-ir
         compiled-module-llvm-module
         compiled-module-context)

;; ---- Compiled module result ------------------------------------------------

(struct compiled-module (context llvm-module ir) #:transparent)

;; ---- Parameters for compilation context ------------------------------------

(define current-ctx       (make-parameter #f))
(define current-builder   (make-parameter #f))
(define current-function  (make-parameter #f))
(define current-env       (make-parameter #f))  ; hash: symbol → llvm-value
(define current-type-env  (make-parameter #f))  ; hash: symbol → ir-type
(define current-funcs     (make-parameter #f))  ; hash: symbol → llvm-function
(define current-func-types (make-parameter #f)) ; hash: symbol → llvm-func-type
(define current-func-env  (make-parameter #f))  ; alist: (name . (param-types ret-type))
(define current-loops     (make-parameter #f))  ; hash: symbol → loop-info
(define current-rec-types (make-parameter #f))  ; hash: symbol → rec-info
(define current-sum-types  (make-parameter #f))  ; hash: symbol → sum-info
(define current-variant->sum (make-parameter #f)) ; hash: variant-name → sum-name

(struct loop-info (header-bb phi-nodes bind-vars) #:transparent)
(struct rec-type-info (llvm-type fields) #:transparent)
;; fields: list of (field-name . ir-type)

;; Sum type: { i32 tag, [payload bytes] }
;; Each variant maps to a tag index + its own struct type for the payload.
(struct sum-type-info (llvm-type variants) #:transparent)
;; variants: list of (variant-name tag-index llvm-payload-type fields)
(struct variant-info (name tag llvm-payload-type fields) #:transparent)
;; fields: list of (field-name . ir-type)

;; ---- Top-level entry point -------------------------------------------------

(define (compile-module decls)
  (Initialize-Native-Target!)
  (define ctx (LLVM-Context-Create))
  (define llvm-mod (LLVM-Module-Create-With-Name-In-Context "safe-module" ctx))

  (define funcs (filter func? decls))
  (define recs  (filter rec? decls))
  (define sums  (filter sum? decls))

  ;; Compile record type declarations
  (define rec-types (make-hash))
  (for ([r (in-list recs)])
    (define fields (rec-fields r))
    (define llvm-field-types
      (for/list ([f (in-list fields)])
        (type->llvm (field-type f) ctx)))
    (define llvm-struct (LLVM-Struct-Create-Named ctx (symbol->string (rec-name r))))
    (LLVM-Struct-Set-Body llvm-struct llvm-field-types (length llvm-field-types) 0)
    (hash-set! rec-types (rec-name r)
               (rec-type-info llvm-struct
                              (for/list ([f (in-list fields)])
                                (cons (field-name f) (field-type f))))))

  ;; Compile sum (tagged union) type declarations
  ;; Layout: { i32 tag, [payload] } where payload is the largest variant's struct.
  (define sum-types (make-hash))
  (for ([s (in-list sums)])
    (define i32-t (LLVM-Int32-Type-In-Context ctx))
    (define variants-info
      (for/list ([v (in-list (sum-variants s))] [tag (in-naturals)])
        (define fields (variant-fields v))
        (define field-llvm-types
          (for/list ([f (in-list fields)])
            (type->llvm (field-type f) ctx)))
        ;; Create a struct for this variant's payload
        (define payload-struct
          (if (null? field-llvm-types)
              #f  ; no payload
              (let ([st (LLVM-Struct-Type-In-Context
                         ctx field-llvm-types (length field-llvm-types) 0)])
                st)))
        (variant-info (variant-name v) tag payload-struct
                      (for/list ([f (in-list fields)])
                        (cons (field-name f) (field-type f))))))
    ;; The union type is { i32, [max-payload-size bytes] }
    ;; For simplicity, use { i32, largest-payload-struct }.
    ;; If no variants have fields, just { i32 }.
    (define payload-types
      (filter values (map variant-info-llvm-payload-type variants-info)))
    ;; Use an i8 array of max size for the payload. Simpler: just use the
    ;; largest variant struct directly. For now, use a struct with tag + i64
    ;; as a fixed-size payload that fits common cases.
    ;; Actually, use { i32 tag, [8 x i8] } as a generic payload.
    ;; Better: { i32, max-variant-struct }.
    ;; Simplest approach that works: use an alloca of { i32, payload-struct }
    ;; per variant during ctor. For match, cast the pointer.
    ;; The "union type" itself is just a pointer — we always pass by pointer.
    ;; Let's create a generic struct { i32 } and handle payload via pointer casts.
    (define union-struct (LLVM-Struct-Create-Named ctx (symbol->string (sum-name s))))
    ;; Make it large enough for any variant: { i32, i64, i64, i64, i64 }
    ;; This is a hack — proper layout would compute max size.
    ;; For now, allocate 32 bytes of payload (handles up to 4 doubles).
    (define i64-t (LLVM-Int64-Type-In-Context ctx))
    (LLVM-Struct-Set-Body union-struct (list i32-t i64-t i64-t i64-t i64-t) 5 0)
    (hash-set! sum-types (sum-name s) (sum-type-info union-struct variants-info)))

  ;; Also register variant→sum mapping for ctor compilation
  (define variant->sum (make-hash))
  (for ([s (in-list sums)])
    (for ([v (in-list (sum-variants s))])
      (hash-set! variant->sum (variant-name v) (sum-name s))))

  ;; Build func-env incrementally: validate each function, accumulating
  ;; the env with known return types so later functions can call earlier ones.
  (define func-env
    (let loop ([remaining funcs] [env '()])
      (if (null? remaining)
          env
          (let* ([f (car remaining)]
                 [params (formals-vars (func-formals f))]
                 [param-types (map variable-type params)]
                 [ret-type (validate-func f env)]
                 [new-env (cons (cons (func-name f) (list param-types ret-type)) env)])
            (loop (cdr remaining) new-env)))))

  ;; Declare all LLVM functions
  (define llvm-funcs (make-hash))
  (define llvm-func-types (make-hash))
  (for ([f (in-list funcs)])
    (define entry (assq (func-name f) func-env))
    (define param-types (car (cdr entry)))
    (define ret-type (cadr (cdr entry)))
    (define llvm-pts (map (lambda (t) (type->llvm t ctx)) param-types))
    (define llvm-rt (type->llvm ret-type ctx))
    (define ft (LLVM-Function-Type llvm-rt llvm-pts (length llvm-pts) 0))
    (define llvm-fn (LLVM-Add-Function llvm-mod (symbol->string (func-name f)) ft))
    (hash-set! llvm-funcs (func-name f) llvm-fn)
    (hash-set! llvm-func-types (func-name f) ft))

  ;; Compile each function body
  (for ([f (in-list funcs)])
    (define llvm-fn (hash-ref llvm-funcs (func-name f)))
    (define params (formals-vars (func-formals f)))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (define entry-bb (LLVM-Append-Basic-Block-In-Context ctx llvm-fn "entry"))
    (LLVM-Position-Builder-At-End bld entry-bb)

    (define env (make-hash))
    (define type-env (make-hash))
    (for ([p (in-list params)] [i (in-naturals)])
      (hash-set! env (variable-name p) (LLVM-Get-Param llvm-fn i))
      (hash-set! type-env (variable-name p) (variable-type p)))

    (parameterize ([current-ctx ctx]
                   [current-builder bld]
                   [current-function llvm-fn]
                   [current-env env]
                   [current-type-env type-env]
                   [current-funcs llvm-funcs]
                   [current-func-types llvm-func-types]
                   [current-func-env func-env]
                   [current-loops (make-hash)]
                   [current-rec-types rec-types]
                   [current-sum-types sum-types]
                   [current-variant->sum variant->sum])
      (define result (emit-body (func-body f)))
      (LLVM-Build-Ret bld result)))

  (LLVM-Verify-Module llvm-mod 'LLVMReturnStatusAction)

  (define ir-ptr (LLVM-Print-Module-To-String llvm-mod))
  (define ir (cast ir-ptr _pointer _string))
  (LLVM-Dispose-Message ir-ptr)

  (compiled-module ctx llvm-mod ir))

;; ---- Type mapping ----------------------------------------------------------

(define (type->llvm t ctx [rec-types #f] [sum-types* #f])
  (cond
    [(prim-type? t)
     (define tag (prim-type-tag t))
     (case tag
       [(i1)   (LLVM-Int1-Type-In-Context ctx)]
       [(i8)   (LLVM-Int8-Type-In-Context ctx)]
       [(i16)  (LLVM-Int16-Type-In-Context ctx)]
       [(i32)  (LLVM-Int32-Type-In-Context ctx)]
       [(i64)  (LLVM-Int64-Type-In-Context ctx)]
       [(f32)  (LLVM-Float-Type-In-Context ctx)]
       [(f64)  (LLVM-Double-Type-In-Context ctx)]
       [(void) (LLVM-Void-Type-In-Context ctx)]
       [else   (error 'type->llvm "unsupported prim type: ~a" t)])]
    [(type-ref? t)
     ;; Look up in rec or sum types — return pointer to the struct.
     (define name (type-ref-name t))
     (define ptr-ty (LLVM-Pointer-Type-In-Context ctx 0))
     ptr-ty]  ; all user-defined types are passed as opaque pointers
    [else (error 'type->llvm "unsupported type: ~a" t)]))

;; ---- Emission helpers (use parameters) -------------------------------------

(define (bld) (current-builder))
(define (ctx) (current-ctx))
(define (fn)  (current-function))

(define (env-ref name)
  (hash-ref (current-env) name
            (lambda () (error 'compile "unbound: ~a" name))))

(define (env-set! name val type)
  (hash-set! (current-env) name val)
  (hash-set! (current-type-env) name type))

(define (lookup-type name)
  (hash-ref (current-type-env) name
            (lambda () #f)))

;; ---- Body emission ---------------------------------------------------------

(define (emit-body b)
  (define exprs (body-exprs b))
  (for/last ([e (in-list exprs)])
    (emit-expr e)))

;; for/last: evaluate all, return the last value
(define-syntax-rule (for/last ([x seq]) body ...)
  (let ([result #f])
    (for ([x seq]) (set! result (let () body ...)))
    result))

;; ---- Expression emission ---------------------------------------------------

(define (emit-expr expr)
  (cond
    [(lit? expr)             (emit-lit expr)]
    [(ref? expr)             (env-ref (ref-name expr))]
    [(op-app? expr)          (emit-op expr)]
    [(icmp-app? expr)        (emit-icmp expr)]
    [(fcmp-app? expr)        (emit-fcmp expr)]
    [(if-form? expr)         (emit-if expr)]
    [(named-bindings? expr)  (emit-named-bindings expr)]
    [(rec-new? expr)         (emit-rec-new expr)]
    [(field-ref? expr)       (emit-field-ref expr)]
    [(ctor? expr)            (emit-ctor expr)]
    [(match-variant? expr)   (emit-match-variant expr)]
    [(app? expr)             (emit-app expr)]
    [(body? expr)            (emit-body expr)]
    [else (error 'compile "unsupported: ~a" expr)]))

;; ---- Literals --------------------------------------------------------------

(define (emit-lit expr)
  (define t (lit-type expr))
  (define v (lit-value expr))
  (define tag (prim-type-tag t))
  (cond
    [(memq tag '(f32 f64))
     (LLVM-Const-Real (type->llvm t (ctx)) (exact->inexact v))]
    [else
     ;; For negative integers, convert to unsigned two's complement.
     (define bits (case tag [(i1) 1] [(i8) 8] [(i16) 16] [(i32) 32] [(i64) 64] [else 64]))
     (define uv (if (< v 0) (+ (expt 2 bits) v) v))
     (LLVM-Const-Int (type->llvm t (ctx)) uv 0)]))

;; ---- Operators -------------------------------------------------------------

(define (expr-is-float? expr)
  (cond
    [(lit? expr) (memq (prim-type-tag (lit-type expr)) '(f32 f64))]
    [(ref? expr)
     (define t (lookup-type (ref-name expr)))
     (and t (prim-type? t) (memq (prim-type-tag t) '(f32 f64)))]
    [(op-app? expr)
     (and (pair? (op-app-args expr))
          (expr-is-float? (car (op-app-args expr))))]
    [(field-ref? expr)
     ;; Look up the field's declared type
     (define info (hash-ref (current-rec-types) (field-ref-type-name expr) #f))
     (and info
          (let ([fields (rec-type-info-fields info)])
            (define f (assq (field-ref-field-name expr) fields))
            (and f (prim-type? (cdr f)) (memq (prim-type-tag (cdr f)) '(f32 f64)))))]
    [else #f]))

(define (emit-op expr)
  (define sym (op-app-operator expr))
  (define args (map emit-expr (op-app-args expr)))
  (define fl? (expr-is-float? (car (op-app-args expr))))
  (define b (bld))
  (cond
    [(= (length args) 2)
     (define a (first args)) (define d (second args))
     (case sym
       [(+) (if fl? (LLVM-Build-FAdd b a d "") (LLVM-Build-Add b a d ""))]
       [(-) (if fl? (LLVM-Build-FSub b a d "") (LLVM-Build-Sub b a d ""))]
       [(*) (if fl? (LLVM-Build-FMul b a d "") (LLVM-Build-Mul b a d ""))]
       [(/) (if fl? (LLVM-Build-FDiv b a d "") (LLVM-Build-SDiv b a d ""))]
       [(bit-and) (LLVM-Build-And b a d "")]
       [(bit-or)  (LLVM-Build-Or b a d "")]
       [(bit-xor) (LLVM-Build-Xor b a d "")]
       [(shl)     (LLVM-Build-Shl b a d "")]
       [(shr)     (LLVM-Build-LShr b a d "")]
       [else (error 'compile "unknown binop: ~a" sym)])]
    [(= (length args) 1)
     (define a (first args))
     (case sym
       [(neg)     (if fl? (LLVM-Build-FNeg b a "") (LLVM-Build-Neg b a ""))]
       [(bit-not) (LLVM-Build-Not b a "")]
       [else (error 'compile "unknown unop: ~a" sym)])]
    [else (error 'compile "bad arity for ~a" sym)]))

;; ---- Comparisons -----------------------------------------------------------

(define (icmp-pred->llvm p)
  (case p [(=) 'LLVMIntEQ] [(!=) 'LLVMIntNE]
          [(<) 'LLVMIntSLT] [(<=) 'LLVMIntSLE]
          [(>) 'LLVMIntSGT] [(>=) 'LLVMIntSGE]
          [else (error 'compile "unknown icmp: ~a" p)]))

(define (emit-icmp expr)
  (define args (map emit-expr (icmp-app-args expr)))
  (LLVM-Build-ICmp (bld) (icmp-pred->llvm (icmp-app-predicate expr))
                   (first args) (second args) ""))

(define (fcmp-pred->llvm p)
  (case p [(=) 'LLVMRealOEQ] [(!=) 'LLVMRealONE]
          [(<) 'LLVMRealOLT] [(<=) 'LLVMRealOLE]
          [(>) 'LLVMRealOGT] [(>=) 'LLVMRealOGE]
          [else (error 'compile "unknown fcmp: ~a" p)]))

(define (emit-fcmp expr)
  (define args (map emit-expr (fcmp-app-args expr)))
  (LLVM-Build-FCmp (bld) (fcmp-pred->llvm (fcmp-app-predicate expr))
                   (first args) (second args) ""))

;; ---- If --------------------------------------------------------------------

(define LLVMGetBasicBlockTerminator
  (get-ffi-obj "LLVMGetBasicBlockTerminator" llvm-lib
               (_fun _LLVM-Basic-Block-Ref -> _pointer)))

(define (block-terminated? bb)
  (not (not (LLVMGetBasicBlockTerminator bb))))

(define (emit-if expr)
  (define cond-val (emit-expr (if-form-condition expr)))
  (define b (bld)) (define c (ctx)) (define f (fn))

  (define then-bb (LLVM-Append-Basic-Block-In-Context c f "then"))
  (define else-bb (LLVM-Append-Basic-Block-In-Context c f "else"))
  (define merge-bb (LLVM-Append-Basic-Block-In-Context c f "merge"))

  (LLVM-Build-Cond-Br b cond-val then-bb else-bb)

  ;; Then
  (LLVM-Position-Builder-At-End b then-bb)
  (define then-val (emit-expr (if-form-then expr)))
  (define then-exit (LLVM-Get-Insert-Block b))
  (define then-terminated? (block-terminated? then-exit))
  (unless then-terminated? (LLVM-Build-Br b merge-bb))

  ;; Else
  (LLVM-Position-Builder-At-End b else-bb)
  (define else-val (emit-expr (if-form-else expr)))
  (define else-exit (LLVM-Get-Insert-Block b))
  (define else-terminated? (block-terminated? else-exit))
  (unless else-terminated? (LLVM-Build-Br b merge-bb))

  ;; Merge — only add phi incoming for non-terminated branches
  (LLVM-Position-Builder-At-End b merge-bb)
  (define ret-type (infer-result-llvm-type (if-form-then expr)))
  (define phi (LLVM-Build-Phi b ret-type ""))
  (define incoming-vals '())
  (define incoming-bbs '())
  (unless then-terminated?
    (set! incoming-vals (cons then-val incoming-vals))
    (set! incoming-bbs (cons then-exit incoming-bbs)))
  (unless else-terminated?
    (set! incoming-vals (cons else-val incoming-vals))
    (set! incoming-bbs (cons else-exit incoming-bbs)))
  (when (pair? incoming-vals)
    (LLVM-Add-Incoming phi incoming-vals incoming-bbs (length incoming-vals)))
  phi)

;; Infer LLVM type of an expression from the type env.
(define (infer-result-llvm-type expr)
  (define c (ctx))
  (cond
    [(lit? expr) (type->llvm (lit-type expr) c)]
    [(ref? expr)
     (define t (lookup-type (ref-name expr)))
     (if t (type->llvm t c) (LLVM-Int32-Type-In-Context c))]
    [(body? expr)
     (define exprs (body-exprs expr))
     (if (pair? exprs)
         (infer-result-llvm-type (last exprs))
         (LLVM-Int32-Type-In-Context c))]
    [else (LLVM-Int32-Type-In-Context c)]))

;; ---- Named bindings (loop) -------------------------------------------------

(define (emit-named-bindings expr)
  (define b (bld)) (define c (ctx)) (define f (fn))
  (define loop-name (named-bindings-name expr))
  (define binds (named-bindings-binds expr))

  ;; Compile initial values in current block
  (define init-vals
    (for/list ([bd (in-list binds)])
      (emit-expr (bind-init bd))))
  (define pre-header-bb (LLVM-Get-Insert-Block b))

  ;; Create loop header block and branch to it
  (define loop-bb (LLVM-Append-Basic-Block-In-Context c f "loop"))
  (LLVM-Build-Br b loop-bb)
  (LLVM-Position-Builder-At-End b loop-bb)

  ;; Create phi nodes for each bind variable
  (define phis
    (for/list ([bd (in-list binds)])
      (define t (variable-type (bind-variable bd)))
      (LLVM-Build-Phi b (type->llvm t c) "")))

  ;; Set initial incoming values (from pre-header)
  (for ([phi (in-list phis)] [init (in-list init-vals)])
    (LLVM-Add-Incoming phi (list init) (list pre-header-bb) 1))

  ;; Bind loop variables in env
  (for ([bd (in-list binds)] [phi (in-list phis)])
    (env-set! (variable-name (bind-variable bd))
              phi
              (variable-type (bind-variable bd))))

  ;; Register loop for recurrence
  (hash-set! (current-loops) loop-name
             (loop-info loop-bb phis
                        (map (lambda (bd) (variable-name (bind-variable bd))) binds)))

  ;; Compile loop body
  (define result (emit-body (named-bindings-body expr)))

  result)

;; ---- Function / loop application -------------------------------------------

(define (emit-app expr)
  (define callee (app-callee expr))
  (unless (ref? callee) (error 'compile "callee must be ref"))
  (define name (ref-name callee))

  ;; Check if it's a loop recurrence
  (define loop (hash-ref (current-loops) name #f))
  (cond
    [loop
     ;; Loop recurrence: compute new values, add incoming to phis, branch back
     (define b (bld))
     (define new-vals
       (for/list ([a (in-list (app-args expr))])
         (emit-expr a)))
     (define back-bb (LLVM-Get-Insert-Block b))
     (for ([phi (in-list (loop-info-phi-nodes loop))]
           [val (in-list new-vals)])
       (LLVM-Add-Incoming phi (list val) (list back-bb) 1))
     (LLVM-Build-Br b (loop-info-header-bb loop))
     ;; Return a dummy value — the loop result comes from the non-recursive branch
     ;; which is captured by the if-form's phi in the merge block.
     ;; Actually, this branch is dead code after the Br. The if-form handles the value.
     ;; Return the first phi as a placeholder (won't be used).
     (car (loop-info-phi-nodes loop))]

    [else
     ;; Function call
     (define llvm-fn (hash-ref (current-funcs) name
                               (lambda () (error 'compile "unknown function: ~a" name))))
     (define ft (hash-ref (current-func-types) name))
     (define args (for/list ([a (in-list (app-args expr))]) (emit-expr a)))
     (LLVM-Build-Call2 (bld) ft llvm-fn args (length args) "")]))

;; ---- Record construction and field access ----------------------------------

(define (emit-rec-new expr)
  (define b (bld)) (define c (ctx))
  (define type-name (rec-new-type-name expr))
  (define info (hash-ref (current-rec-types) type-name
                         (lambda () (error 'compile "unknown record type: ~a" type-name))))
  (define llvm-struct-type (rec-type-info-llvm-type info))

  ;; Alloca the struct on the stack
  (define ptr (LLVM-Build-Alloca b llvm-struct-type ""))

  ;; Store each field value via GEP
  (define field-vals (map emit-expr (rec-new-args expr)))
  (define i32-type (LLVM-Int32-Type-In-Context c))
  (for ([val (in-list field-vals)]
        [i (in-naturals)])
    (define idx (LLVM-Const-Int i32-type i 0))
    (define zero (LLVM-Const-Int i32-type 0 0))
    (define field-ptr (LLVM-Build-GEP2 b llvm-struct-type ptr (list zero idx) 2 ""))
    (LLVM-Build-Store b val field-ptr))

  ;; Return the pointer to the struct
  ptr)

(define (emit-field-ref expr)
  (define b (bld)) (define c (ctx))
  (define type-name (field-ref-type-name expr))
  (define fname (field-ref-field-name expr))
  (define info (hash-ref (current-rec-types) type-name
                         (lambda () (error 'compile "unknown record type: ~a" type-name))))
  (define llvm-struct-type (rec-type-info-llvm-type info))
  (define fields (rec-type-info-fields info))

  ;; Find field index
  (define field-idx
    (for/or ([f (in-list fields)] [i (in-naturals)])
      (and (eq? (car f) fname) i)))
  (unless field-idx
    (error 'compile "unknown field ~a in record ~a" fname type-name))

  ;; Get field type for the load
  (define field-ir-type (cdr (list-ref fields field-idx)))
  (define field-llvm-type (type->llvm field-ir-type c))

  ;; Compile the sub-expression (should be a pointer to the struct)
  (define struct-ptr (emit-expr (field-ref-expr expr)))

  ;; GEP to the field and load
  (define i32-type (LLVM-Int32-Type-In-Context c))
  (define zero (LLVM-Const-Int i32-type 0 0))
  (define idx (LLVM-Const-Int i32-type field-idx 0))
  (define field-ptr (LLVM-Build-GEP2 b llvm-struct-type struct-ptr (list zero idx) 2 ""))
  (LLVM-Build-Load2 b field-llvm-type field-ptr ""))

;; ---- Tagged union construction and matching --------------------------------

(define (emit-ctor expr)
  (define b (bld)) (define c (ctx))
  (define vname (ctor-variant-name expr))
  (define sum-name (hash-ref (current-variant->sum) vname
                              (lambda () (error 'compile "unknown variant: ~a" vname))))
  (define sinfo (hash-ref (current-sum-types) sum-name))
  (define union-type (sum-type-info-llvm-type sinfo))
  (define vinfo (for/or ([vi (in-list (sum-type-info-variants sinfo))])
                  (and (eq? (variant-info-name vi) vname) vi)))
  (unless vinfo (error 'compile "variant not found: ~a" vname))

  (define i32-type (LLVM-Int32-Type-In-Context c))

  ;; Alloca the union struct
  (define ptr (LLVM-Build-Alloca b union-type ""))

  ;; Store tag (field 0)
  (define zero (LLVM-Const-Int i32-type 0 0))
  (define tag-ptr (LLVM-Build-GEP2 b union-type ptr (list zero zero) 2 ""))
  (LLVM-Build-Store b (LLVM-Const-Int i32-type (variant-info-tag vinfo) 0) tag-ptr)

  ;; Store payload fields (if any)
  (define payload-type (variant-info-llvm-payload-type vinfo))
  (when payload-type
    (define args (map emit-expr (ctor-args expr)))
    ;; Cast the pointer to payload struct pointer (starting at field 1)
    (define one (LLVM-Const-Int i32-type 1 0))
    (define payload-raw-ptr (LLVM-Build-GEP2 b union-type ptr (list zero one) 2 ""))
    (define payload-ptr (LLVM-Build-Bit-Cast b payload-raw-ptr
                                             (LLVM-Pointer-Type-In-Context c 0) ""))
    (for ([val (in-list args)] [i (in-naturals)])
      (define idx (LLVM-Const-Int i32-type i 0))
      (define field-ptr (LLVM-Build-GEP2 b payload-type payload-ptr
                                         (list zero idx) 2 ""))
      (LLVM-Build-Store b val field-ptr)))

  ptr)

(define (emit-match-variant expr)
  (define b (bld)) (define c (ctx)) (define f (fn))
  (define scrutinee (emit-expr (match-variant-scrutinee expr)))
  (define cases (match-variant-cases expr))

  ;; Determine which sum type this is
  ;; Look at the first case's pattern to find the variant name
  (define first-vname (ctor-pat-variant-name (match-case-pattern (car cases))))
  (define sum-name (hash-ref (current-variant->sum) first-vname
                              (lambda () (error 'compile "unknown variant: ~a" first-vname))))
  (define sinfo (hash-ref (current-sum-types) sum-name))
  (define union-type (sum-type-info-llvm-type sinfo))

  (define i32-type (LLVM-Int32-Type-In-Context c))
  (define zero (LLVM-Const-Int i32-type 0 0))

  ;; Load the tag
  (define tag-ptr (LLVM-Build-GEP2 b union-type scrutinee (list zero zero) 2 ""))
  (define tag (LLVM-Build-Load2 b i32-type tag-ptr ""))

  ;; Create basic blocks for each case + merge
  (define merge-bb (LLVM-Append-Basic-Block-In-Context c f "match.merge"))
  (define case-bbs
    (for/list ([_ (in-list cases)])
      (LLVM-Append-Basic-Block-In-Context c f "match.case")))
  (define default-bb (last case-bbs))

  ;; Switch on tag
  (define sw (LLVM-Build-Switch b tag default-bb (length cases)))
  (for ([cs (in-list cases)]
        [bb (in-list case-bbs)])
    (define vname (ctor-pat-variant-name (match-case-pattern cs)))
    (define vinfo (for/or ([vi (in-list (sum-type-info-variants sinfo))])
                    (and (eq? (variant-info-name vi) vname) vi)))
    (LLVM-Add-Case sw (LLVM-Const-Int i32-type (variant-info-tag vinfo) 0) bb))

  ;; Compile each case
  (define case-results
    (for/list ([cs (in-list cases)]
               [bb (in-list case-bbs)])
      (LLVM-Position-Builder-At-End b bb)
      (define pat (match-case-pattern cs))
      (define vname (ctor-pat-variant-name pat))
      (define bindings (ctor-pat-bindings pat))
      (define vinfo (for/or ([vi (in-list (sum-type-info-variants sinfo))])
                      (and (eq? (variant-info-name vi) vname) vi)))

      ;; Bind pattern variables by extracting from payload
      (when (and vinfo (variant-info-llvm-payload-type vinfo) (pair? bindings))
        (define payload-type (variant-info-llvm-payload-type vinfo))
        (define one (LLVM-Const-Int i32-type 1 0))
        (define payload-raw-ptr (LLVM-Build-GEP2 b union-type scrutinee
                                                 (list zero one) 2 ""))
        (define payload-ptr (LLVM-Build-Bit-Cast b payload-raw-ptr
                                                 (LLVM-Pointer-Type-In-Context c 0) ""))
        (for ([v (in-list bindings)] [i (in-naturals)])
          (define idx (LLVM-Const-Int i32-type i 0))
          (define field-ptr (LLVM-Build-GEP2 b payload-type payload-ptr
                                             (list zero idx) 2 ""))
          (define field-val (LLVM-Build-Load2 b (type->llvm (variable-type v) c) field-ptr ""))
          (env-set! (variable-name v) field-val (variable-type v))))

      ;; Compile case body
      (define result (emit-body (match-case-body cs)))
      (define exit-bb (LLVM-Get-Insert-Block b))
      (LLVM-Build-Br b merge-bb)
      (cons result exit-bb)))

  ;; Merge with phi
  (LLVM-Position-Builder-At-End b merge-bb)
  (define result-type
    ;; Infer from first case's body
    (infer-result-llvm-type (match-case-body (car cases))))
  (define phi (LLVM-Build-Phi b result-type ""))
  (define vals (map car case-results))
  (define bbs (map cdr case-results))
  (LLVM-Add-Incoming phi vals bbs (length vals))
  phi)
