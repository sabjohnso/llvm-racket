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
(define current-malloc     (make-parameter #f))  ; (cons malloc-fn malloc-ft)
(define current-overloaded (make-parameter #f))  ; hash: name → overloaded-intrinsic
(define current-llvm-mod   (make-parameter #f))  ; LLVM module ref (for declaring intrinsics)

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

  (define funcs      (filter func? decls))
  (define recs       (filter rec? decls))
  (define sums       (filter sum? decls))
  (define intrinsics (filter intrinsic-func? decls))
  (define overloaded (filter overloaded-intrinsic? decls))

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

  ;; Seed func-env with intrinsic function signatures so user functions
  ;; can call them and type-check correctly.
  (define intrinsic-env
    (for/list ([i (in-list intrinsics)])
      (cons (intrinsic-func-name i)
            (list (intrinsic-func-param-types i)
                  (intrinsic-func-ret-type i)))))

  ;; Add overloaded intrinsics to the env with 'overloaded marker.
  ;; The type checker uses first-arg type as the return type.
  (define overloaded-env
    (for/list ([o (in-list overloaded)])
      (cons (overloaded-intrinsic-name o) (list 'overloaded (overloaded-intrinsic-arity o)))))

  ;; Build rec-env for field type lookups: (type-name . field-name) → field-type
  (define rec-field-env
    (for*/hash ([r (in-list recs)]
                [f (in-list (rec-fields r))])
      (values (cons (rec-name r) (field-name f)) (field-type f))))

  ;; Build func-env with all function names visible (forward references OK).
  ;; Pass 1: seed all names with param types and #f return types.
  ;; Pass 2: validate each function with all names visible, fill in return types.
  ;; If pass 2 resolves new types, repeat until stable (handles transitive deps).
  (define base-env (append overloaded-env intrinsic-env))
  (define initial-func-entries
    (for/list ([f (in-list funcs)])
      (define params (formals-vars (func-formals f)))
      (cons (func-name f) (list (map variable-type params) #f))))
  (define func-env
    (let pass ([env (append initial-func-entries base-env)]
               [iterations 0])
      (define-values (new-env changed?)
        (for/fold ([e env] [any-change? #f])
                  ([f (in-list funcs)])
          (define old-entry (assq (func-name f) e))
          (define old-ret (and old-entry (cadr (cdr old-entry))))
          (define ret-type
            (with-handlers ([exn:fail? (lambda (_) #f)])
              (validate-func f e rec-field-env variant->sum)))
          (define actual-ret (or ret-type old-ret))
          (define entry-changed? (and ret-type (not (equal? ret-type old-ret))))
          (define params (formals-vars (func-formals f)))
          (define param-types (map variable-type params))
          (define updated-e
            (cons (cons (func-name f) (list param-types actual-ret))
                  (filter (lambda (p) (not (eq? (car p) (func-name f)))) e)))
          (values updated-e (or any-change? entry-changed?))))
      (if (and changed? (< iterations 5))
          (pass new-env (add1 iterations))
          new-env)))

  ;; Declare LLVM intrinsic functions first (user funcs may shadow them)
  (define llvm-funcs (make-hash))
  (define llvm-func-types (make-hash))
  (for ([i (in-list intrinsics)])
    (define llvm-pts (map (lambda (t) (type->llvm t ctx))
                          (intrinsic-func-param-types i)))
    (define llvm-rt (type->llvm (intrinsic-func-ret-type i) ctx))
    (define ft (LLVM-Function-Type llvm-rt llvm-pts (length llvm-pts) 0))
    (define llvm-fn (LLVM-Add-Function llvm-mod (intrinsic-func-llvm-name i) ft))
    (hash-set! llvm-funcs (intrinsic-func-name i) llvm-fn)
    (hash-set! llvm-func-types (intrinsic-func-name i) ft))

  ;; Declare user functions (shadows intrinsics with the same name)
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

  ;; Declare malloc for heap allocation of records/unions returned across FFI.
  ;; malloc(i64) -> ptr
  (define i64-type (LLVM-Int64-Type-In-Context ctx))
  (define ptr-type-llvm (LLVM-Pointer-Type-In-Context ctx 0))
  (define malloc-ft (LLVM-Function-Type ptr-type-llvm (list i64-type) 1 0))
  (define malloc-fn (LLVM-Add-Function llvm-mod "malloc" malloc-ft))

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
                   [current-variant->sum variant->sum]
                   [current-malloc (cons malloc-fn malloc-ft)]
                   [current-overloaded
                    (for/hash ([o (in-list overloaded)])
                      (values (overloaded-intrinsic-name o) o))]
                   [current-llvm-mod llvm-mod])
      (define result (emit-body (func-body f)))
      ;; Emit ret or ret void depending on return type
      (define entry (assq (func-name f) func-env))
      (define ret-type (and entry (cadr (cdr entry))))
      (if (and ret-type (prim-type? ret-type)
               (eq? (prim-type-tag ret-type) 'void))
          (LLVM-Build-Ret-Void bld)
          (LLVM-Build-Ret bld result))))

  ;; Generate FFI wrapper functions for functions with vec-type params or return.
  ;; The wrapper takes ptr params (for vectors), loads them as LLVM vectors,
  ;; calls the real function, and stores vec results to an out-param pointer.
  (for ([f (in-list funcs)])
    (define entry (assq (func-name f) func-env))
    (define param-types (car (cdr entry)))
    (define ret-type (cadr (cdr entry)))
    (define has-vec-params? (ormap vec-type? param-types))
    (define has-vec-return? (vec-type? ret-type))
    (when (or has-vec-params? has-vec-return?)
      (define wrapper-name (string-append (symbol->string (func-name f)) "__wrapper"))
      (define ptr-t (LLVM-Pointer-Type-In-Context ctx 0))
      ;; Wrapper params: ptr for vec-type params, scalar for others.
      ;; If return is vec-type, add an extra ptr out-param at the end.
      (define wrapper-param-types
        (append
         (for/list ([pt (in-list param-types)])
           (if (vec-type? pt) ptr-t (type->llvm pt ctx)))
         (if has-vec-return? (list ptr-t) '())))
      ;; Wrapper always returns void when result is vec (stored via out-param)
      (define wrapper-ret-type
        (if has-vec-return?
            (LLVM-Void-Type-In-Context ctx)
            (type->llvm ret-type ctx)))
      (define wrapper-ft (LLVM-Function-Type wrapper-ret-type wrapper-param-types
                                             (length wrapper-param-types) 0))
      (define wrapper-fn (LLVM-Add-Function llvm-mod wrapper-name wrapper-ft))
      ;; Build wrapper body
      (define wb (LLVM-Create-Builder-In-Context ctx))
      (define wentry (LLVM-Append-Basic-Block-In-Context ctx wrapper-fn "entry"))
      (LLVM-Position-Builder-At-End wb wentry)
      ;; Load vector params from pointers element-by-element (avoids alignment issues).
      ;; Scalar params pass through unchanged.
      (define i32-type (LLVM-Int32-Type-In-Context ctx))
      (define call-args
        (for/list ([pt (in-list param-types)] [i (in-naturals)])
          (define param (LLVM-Get-Param wrapper-fn i))
          (if (vec-type? pt)
              ;; Load each element and build vector via insert-element chain
              (let* ([elem-llvm-t (type->llvm (vec-type-element pt) ctx)]
                     [vec-llvm-t (type->llvm pt ctx)]
                     [n (vec-type-count pt)])
                (for/fold ([vec (LLVM-Get-Undef vec-llvm-t)])
                          ([j (in-range n)])
                  (define idx (LLVM-Const-Int i32-type j 0))
                  (define elem-ptr (LLVM-Build-GEP2 wb elem-llvm-t param
                                                    (list idx) 1 ""))
                  (define elem-val (LLVM-Build-Load2 wb elem-llvm-t elem-ptr ""))
                  (LLVM-Build-Insert-Element wb vec elem-val idx "")))
              param)))
      ;; Call the real function
      (define real-fn (hash-ref llvm-funcs (func-name f)))
      (define real-ft (hash-ref llvm-func-types (func-name f)))
      (define result (LLVM-Build-Call2 wb real-ft real-fn call-args (length call-args) ""))
      ;; Return: store vec result to out-param, or return scalar directly
      (cond
        [has-vec-return?
         ;; Store result vector element-by-element to the out-param pointer
         (define out-param (LLVM-Get-Param wrapper-fn (length param-types)))
         (define elem-llvm-t (type->llvm (vec-type-element ret-type) ctx))
         (define n (vec-type-count ret-type))
         (for ([j (in-range n)])
           (define idx (LLVM-Const-Int i32-type j 0))
           (define elem-val (LLVM-Build-Extract-Element wb result idx ""))
           (define elem-ptr (LLVM-Build-GEP2 wb elem-llvm-t out-param
                                             (list idx) 1 ""))
           (LLVM-Build-Store wb elem-val elem-ptr))
         (LLVM-Build-Ret-Void wb)]
        [(and (prim-type? ret-type) (eq? (prim-type-tag ret-type) 'void))
         (LLVM-Build-Ret-Void wb)]
        [else
         (LLVM-Build-Ret wb result)])))

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
    [(vec-type? t)
     (LLVM-Vector-Type (type->llvm (vec-type-element t) ctx)
                       (vec-type-count t))]
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
    [(void-expr? expr)       #f]  ; void — no value
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
    [(vec-lit? expr)         (emit-vec-lit expr)]
    [(vec-extract? expr)     (emit-vec-extract expr)]
    [(vec-insert? expr)      (emit-vec-insert expr)]
    [(vec-shuffle? expr)     (emit-vec-shuffle expr)]
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

;; ---- LLVM type name mangling -----------------------------------------------

;; Convert an IR type to the LLVM intrinsic name suffix.
;; e.g., f64 → "f64", (vec-type f64 4) → "v4f64", i32 → "i32"
(define (ir-type->llvm-suffix t)
  (cond
    [(prim-type? t)
     (case (prim-type-tag t)
       [(f64) "f64"] [(f32) "f32"]
       [(i1) "i1"] [(i8) "i8"] [(i16) "i16"] [(i32) "i32"] [(i64) "i64"]
       [else (error 'ir-type->llvm-suffix "unsupported: ~a" t)])]
    [(vec-type? t)
     (format "v~a~a" (vec-type-count t) (ir-type->llvm-suffix (vec-type-element t)))]
    [else (error 'ir-type->llvm-suffix "unsupported: ~a" t)]))

;; ---- Operators -------------------------------------------------------------

(define (ir-type-is-float? t)
  (cond
    [(and t (prim-type? t)) (memq (prim-type-tag t) '(f32 f64))]
    [(and t (vec-type? t))  (ir-type-is-float? (vec-type-element t))]
    [else #f]))

(define (expr-is-float? expr)
  (cond
    [(lit? expr) (ir-type-is-float? (lit-type expr))]
    [(ref? expr)
     (ir-type-is-float? (lookup-type (ref-name expr)))]
    [(op-app? expr)
     (and (pair? (op-app-args expr))
          (expr-is-float? (car (op-app-args expr))))]
    [(icmp-app? expr) #f]  ; comparisons return i1
    [(fcmp-app? expr) #f]
    [(if-form? expr) (expr-is-float? (if-form-then expr))]
    [(named-bindings? expr)
     ;; Check the body's last expression
     (define exprs (body-exprs (named-bindings-body expr)))
     (and (pair? exprs) (expr-is-float? (last exprs)))]
    [(app? expr)
     ;; Look up callee's return type in func-env
     (define callee (app-callee expr))
     (and (ref? callee)
          (let ([entry (assq (ref-name callee) (current-func-env))])
            (and entry
                 (if (eq? (car (cdr entry)) 'overloaded)
                     ;; Overloaded intrinsic: return type matches first arg type
                     (and (pair? (app-args expr))
                          (expr-is-float? (car (app-args expr))))
                     (ir-type-is-float? (cadr (cdr entry)))))))]
    [(field-ref? expr)
     (define info (hash-ref (current-rec-types) (field-ref-type-name expr) #f))
     (and info
          (let ([fields (rec-type-info-fields info)])
            (define f (assq (field-ref-field-name expr) fields))
            (and f (ir-type-is-float? (cdr f)))))]
    [(vec-lit? expr) (ir-type-is-float? (vec-lit-element-type expr))]
    [(vec-extract? expr) (expr-is-float? (vec-extract-vec expr))]
    [(vec-insert? expr) (expr-is-float? (vec-insert-vec expr))]
    [(vec-shuffle? expr) (expr-is-float? (vec-shuffle-v1 expr))]
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
    [(op-app? expr)
     (if (and (pair? (op-app-args expr))
              (expr-is-float? (car (op-app-args expr))))
         (LLVM-Double-Type-In-Context c)
         (LLVM-Int32-Type-In-Context c))]
    ;; Records and unions are returned as pointers
    [(rec-new? expr) (LLVM-Pointer-Type-In-Context c 0)]
    [(ctor? expr) (LLVM-Pointer-Type-In-Context c 0)]
    [(field-ref? expr)
     (define info (hash-ref (current-rec-types) (field-ref-type-name expr) #f))
     (if info
         (let ([fields (rec-type-info-fields info)])
           (define f (assq (field-ref-field-name expr) fields))
           (if f (type->llvm (cdr f) c) (LLVM-Int32-Type-In-Context c)))
         (LLVM-Int32-Type-In-Context c))]
    [(if-form? expr) (infer-result-llvm-type (if-form-then expr))]
    [(named-bindings? expr)
     (define exprs (body-exprs (named-bindings-body expr)))
     (if (pair? exprs)
         (infer-result-llvm-type (last exprs))
         (LLVM-Int32-Type-In-Context c))]
    [(app? expr)
     (define callee (app-callee expr))
     (if (ref? callee)
         (let ([entry (assq (ref-name callee) (current-func-env))])
           (if (and entry (cadr (cdr entry)))
               (type->llvm (cadr (cdr entry)) c)
               (LLVM-Int32-Type-In-Context c)))
         (LLVM-Int32-Type-In-Context c))]
    [(vec-lit? expr)
     (LLVM-Vector-Type (type->llvm (vec-lit-element-type expr) c)
                       (length (vec-lit-values expr)))]
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
     ;; Check for overloaded intrinsic
     (define oi (hash-ref (current-overloaded) name #f))
     (cond
       [oi
        ;; Resolve the overloaded intrinsic based on argument types.
        ;; Compile args first to determine their LLVM types.
        (define args (for/list ([a (in-list (app-args expr))]) (emit-expr a)))
        ;; Determine the operand IR type from the compile-time type env.
        ;; Walk the expression to find its type — handles ref, lit, op-app,
        ;; vec-lit, app, and other forms.
        (define first-arg-expr (car (app-args expr)))
        (define (infer-ir-type e)
          (cond
            [(ref? e) (or (lookup-type (ref-name e)) f64)]
            [(lit? e) (lit-type e)]
            [(op-app? e)
             (and (pair? (op-app-args e)) (infer-ir-type (car (op-app-args e))))]
            [(vec-lit? e) (vec-type (vec-lit-element-type e) (length (vec-lit-values e)))]
            [(vec-extract? e) (let ([vt (infer-ir-type (vec-extract-vec e))])
                                (and (vec-type? vt) (vec-type-element vt)))]
            [(vec-insert? e) (infer-ir-type (vec-insert-vec e))]
            [(app? e)
             (and (ref? (app-callee e))
                  (let ([entry (assq (ref-name (app-callee e)) (current-func-env))])
                    (and entry (not (eq? (car (cdr entry)) 'overloaded))
                         (cadr (cdr entry)))))]
            [else f64]))
        (define arg-ir-type (infer-ir-type first-arg-expr))
        ;; Mangle the LLVM name: prefix.type-suffix
        (define type-suffix (ir-type->llvm-suffix arg-ir-type))
        (define mangled-name
          (string-append (overloaded-intrinsic-llvm-prefix oi) "." type-suffix))
        ;; Declare the specific variant if not already in llvm-funcs
        (define existing (hash-ref (current-funcs) (string->symbol mangled-name) #f))
        (define-values (llvm-fn ft)
          (if existing
              (values existing (hash-ref (current-func-types) (string->symbol mangled-name)))
              (let* ([c (ctx)]
                     [llvm-t (type->llvm arg-ir-type c)]
                     [param-ts (make-list (overloaded-intrinsic-arity oi) llvm-t)]
                     [new-ft (LLVM-Function-Type llvm-t param-ts
                                                 (overloaded-intrinsic-arity oi) 0)]
                     [new-fn (LLVM-Add-Function (current-llvm-mod) mangled-name new-ft)])
                (hash-set! (current-funcs) (string->symbol mangled-name) new-fn)
                (hash-set! (current-func-types) (string->symbol mangled-name) new-ft)
                (values new-fn new-ft))))
        (LLVM-Build-Call2 (bld) ft llvm-fn args (length args) "")]
       [else
        ;; Normal function call
        (define llvm-fn (hash-ref (current-funcs) name
                                  (lambda () (error 'compile "unknown function: ~a" name))))
        (define ft (hash-ref (current-func-types) name))
        (define args (for/list ([a (in-list (app-args expr))]) (emit-expr a)))
        (LLVM-Build-Call2 (bld) ft llvm-fn args (length args) "")])]))

;; ---- Vector operations -----------------------------------------------------

(define (emit-vec-lit expr)
  (define elem-type (vec-lit-element-type expr))
  (define vals (vec-lit-values expr))
  (define n (length vals))
  (define compiled-vals (map emit-expr vals))
  ;; Build via insert-element chain from undef
  (define llvm-elem-t (type->llvm elem-type (ctx)))
  (define llvm-vec-t (LLVM-Vector-Type llvm-elem-t n))
  (define i32-t (LLVM-Int32-Type-In-Context (ctx)))
  (for/fold ([vec (LLVM-Get-Undef llvm-vec-t)])
            ([val (in-list compiled-vals)] [i (in-naturals)])
    (LLVM-Build-Insert-Element (bld) vec val
                               (LLVM-Const-Int i32-t i 0) "")))

(define (emit-vec-extract expr)
  (define vec-val (emit-expr (vec-extract-vec expr)))
  (define idx-val (emit-expr (vec-extract-index expr)))
  (LLVM-Build-Extract-Element (bld) vec-val idx-val ""))

(define (emit-vec-insert expr)
  (define vec-val (emit-expr (vec-insert-vec expr)))
  (define idx-val (emit-expr (vec-insert-index expr)))
  (define val (emit-expr (vec-insert-val expr)))
  (LLVM-Build-Insert-Element (bld) vec-val val idx-val ""))

(define (emit-vec-shuffle expr)
  (define v1 (emit-expr (vec-shuffle-v1 expr)))
  (define v2 (emit-expr (vec-shuffle-v2 expr)))
  (define mask-ints (vec-shuffle-mask expr))
  (define i32-t (LLVM-Int32-Type-In-Context (ctx)))
  (define mask-vals (map (lambda (i) (LLVM-Const-Int i32-t i 0)) mask-ints))
  (define mask-vec (LLVM-Const-Vector mask-vals (length mask-vals)))
  (LLVM-Build-Shuffle-Vector (bld) v1 v2 mask-vec ""))

;; ---- Record construction and field access ----------------------------------

(define (emit-rec-new expr)
  (define b (bld)) (define c (ctx))
  (define type-name (rec-new-type-name expr))
  (define info (hash-ref (current-rec-types) type-name
                         (lambda () (error 'compile "unknown record type: ~a" type-name))))
  (define llvm-struct-type (rec-type-info-llvm-type info))

  ;; Heap-allocate the struct via malloc so the pointer survives function return.
  (define i64-type (LLVM-Int64-Type-In-Context c))
  (define struct-size (LLVM-Const-Int i64-type
                        (length (rec-type-info-fields info))
                        0))
  ;; Use a generous size estimate: 8 bytes per field (aligned to i64)
  (define alloc-size (LLVM-Const-Int i64-type
                       (* 8 (length (rec-type-info-fields info)))
                       0))
  (define malloc-pair (current-malloc))
  (define raw-ptr (LLVM-Build-Call2 b (cdr malloc-pair) (car malloc-pair)
                                    (list alloc-size) 1 ""))

  ;; Store each field value via GEP
  (define field-vals (map emit-expr (rec-new-args expr)))
  (define i32-type (LLVM-Int32-Type-In-Context c))
  (for ([val (in-list field-vals)]
        [i (in-naturals)])
    (define idx (LLVM-Const-Int i32-type i 0))
    (define zero (LLVM-Const-Int i32-type 0 0))
    (define field-ptr (LLVM-Build-GEP2 b llvm-struct-type raw-ptr (list zero idx) 2 ""))
    (LLVM-Build-Store b val field-ptr))

  ;; Return the pointer to the heap-allocated struct
  raw-ptr)

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

  ;; Heap-allocate the union struct via malloc
  (define i64-type (LLVM-Int64-Type-In-Context c))
  (define alloc-size (LLVM-Const-Int i64-type 40 0)) ; 4 tag + 32 payload + padding
  (define malloc-pair (current-malloc))
  (define ptr (LLVM-Build-Call2 b (cdr malloc-pair) (car malloc-pair)
                                (list alloc-size) 1 ""))

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

  ;; Compile each case (with scoped env to prevent variable leaking between cases)
  (define saved-env (hash-copy (current-env)))
  (define saved-type-env (hash-copy (current-type-env)))
  (define case-results
    (for/list ([cs (in-list cases)]
               [bb (in-list case-bbs)])
      ;; Restore env to pre-match state for each case
      (hash-clear! (current-env))
      (for ([(k v) (in-hash saved-env)]) (hash-set! (current-env) k v))
      (hash-clear! (current-type-env))
      (for ([(k v) (in-hash saved-type-env)]) (hash-set! (current-type-env) k v))

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
