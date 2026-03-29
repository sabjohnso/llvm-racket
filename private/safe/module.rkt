#lang racket/base

(require ffi/unsafe
         ffi/vector
         racket/list
         racket/string
         "repr.rkt"
         "library.rkt"
         "type-check.rkt"
         "compile.rkt"
         "../ffi/lib.rkt"
         "../ffi/types.rkt"
         "../ffi/core.rkt"
         "../ffi/target.rkt"
         "../ffi/target-machine.rkt"
         "../ffi/passes.rkt"
         "../ffi/orc.rkt"
         "../ffi/disassembler.rkt")

(provide make-llvm-module
         call
         call-fn
         disassemble
         safe-module?
         safe-module-ir)

;; ---- Safe module -----------------------------------------------------------

(struct safe-module (jit func-env ir decls type-registry) #:transparent)

;; ---- make-llvm-module ------------------------------------------------------

(define (make-llvm-module #:optimize [optimize "default<O2>"]
                          #:include [includes '()]
                          #:types [type-registry (hash)]
                          #:cpu [cpu 'native]
                          . decls)
  (Initialize-Native-Target!)

  ;; Splice included library declarations before user declarations
  (define all-decls
    (append (append-map llvm-library-decls includes) decls))

  ;; Compile to LLVM IR
  (define cm (compile-module all-decls))
  (define llvm-mod (compiled-module-llvm-module cm))
  (define ctx (compiled-module-context cm))
  (define ir (compiled-module-ir cm))

  ;; Resolve CPU and features for target machine
  (define-values (cpu-name cpu-features)
    (cond
      [(eq? cpu 'native)
       (values (LLVM-Get-Host-CPU-Name) (LLVM-Get-Host-CPU-Features))]
      [(string? cpu)
       (values cpu "")]
      [else (values "generic" "")]))

  ;; Optimize (unless #f)
  (define triple-ptr (LLVM-Get-Default-Target-Triple))
  (define triple (cast triple-ptr _pointer _string))
  (LLVM-Dispose-Message triple-ptr)
  (define target (LLVM-Get-Target-From-Triple triple))
  (define tm (LLVM-Create-Target-Machine
              target triple cpu-name cpu-features
              'LLVMCodeGenLevelDefault
              'LLVMRelocDefault
              'LLVMCodeModelDefault))
  (when optimize
    (define popts (LLVM-Create-Pass-Builder-Options))
    (LLVM-Run-Passes llvm-mod optimize tm popts))

  ;; Create a fresh JIT per module to avoid symbol conflicts
  (define jit (LLVM-Orc-Create-LLJIT #f))

  ;; Allow JIT to resolve host process symbols (e.g., libm for math intrinsics)
  (define dylib (LLVM-Orc-LLJIT-Get-Main-JIT-Dylib jit))
  (define prefix (LLVM-Orc-LLJIT-Get-Global-Prefix jit))
  (define gen (LLVM-Orc-Create-Dynamic-Library-Search-Generator-For-Process prefix))
  (LLVM-Orc-JIT-Dylib-Add-Generator dylib gen)

  ;; Wrap in thread-safe module and add to JIT
  (define ts-ctx (LLVM-Orc-Create-New-Thread-Safe-Context))
  (define ts-mod (LLVM-Orc-Create-New-Thread-Safe-Module llvm-mod ts-ctx))
  (LLVM-Orc-LLJIT-Add-LLVM-IR-Module jit dylib ts-mod)

  ;; Build func-env for call dispatch (with return types).
  ;; Seed with intrinsic signatures so user func validation can reference them.
  (define intrinsic-env
    (for/list ([i (in-list (filter intrinsic-func? all-decls))])
      (cons (intrinsic-func-name i)
            (list (intrinsic-func-param-types i)
                  (intrinsic-func-ret-type i)))))
  (define overloaded-env
    (for/list ([o (in-list (filter overloaded-intrinsic? all-decls))])
      (cons (overloaded-intrinsic-name o)
            (list 'overloaded (overloaded-intrinsic-arity o)))))
  (define func-env
    (let loop ([remaining (filter func? all-decls)]
               [env (append overloaded-env intrinsic-env)])
      (if (null? remaining)
          env
          (let* ([f (car remaining)]
                 [params (formals-vars (func-formals f))]
                 [param-types (map variable-type params)]
                 [ret-type (validate-func f env)]
                 [new-env (cons (cons (func-name f)
                                      (list param-types ret-type))
                                env)])
            (loop (cdr remaining) new-env)))))

  (safe-module jit func-env ir all-decls type-registry))

;; ---- call ------------------------------------------------------------------

;; Macro that auto-quotes the function name.
(define-syntax-rule (call m fn-name arg ...)
  (call-fn m 'fn-name arg ...))

(define (call-fn m fn-name . args)
  (define jit (safe-module-jit m))
  (define entry (assq fn-name (safe-module-func-env m)))
  (unless entry
    (error 'call-fn "unknown function: ~a" fn-name))
  (define param-types (car (cdr entry)))
  (define ret-type (cadr (cdr entry)))
  (define decls (safe-module-decls m))
  (define registry (safe-module-type-registry m))

  ;; Use wrapper function if any params or return are vec-type
  (define has-vec-params? (ormap vec-type? param-types))
  (define has-vec-return? (vec-type? ret-type))
  (define needs-wrapper? (or has-vec-params? has-vec-return?))
  (define lookup-name
    (if needs-wrapper?
        (string-append (symbol->string fn-name) "__wrapper")
        (symbol->string fn-name)))
  (define addr (LLVM-Orc-LLJIT-Lookup jit lookup-name))

  ;; Marshal arguments: convert Racket values to C values.
  ;; type-ref args get marshalled to heap-allocated struct pointers.
  (define c-params (map (lambda (t) (ir-type->ctype t decls)) param-types))
  (define marshalled-args
    (map (lambda (arg t) (marshal-arg arg t decls registry)) args param-types))

  ;; For vec return via wrapper: allocate output ffi/vector, append its pointer as extra arg
  (define-values (all-c-params all-marshalled-args result-vec)
    (if has-vec-return?
        (let* ([n (vec-type-count ret-type)]
               [tag (prim-type-tag (vec-type-element ret-type))]
               [out-vec (case tag
                          [(f64) (make-f64vector n)]
                          [(f32) (make-f32vector n)]
                          [(i32) (make-s32vector n)]
                          [(i64) (make-s64vector n)]
                          [else (error 'call-fn "unsupported vec element: ~a" tag)])]
               [out-ptr (case tag
                          [(f64) (f64vector->cpointer out-vec)]
                          [(f32) (f32vector->cpointer out-vec)]
                          [(i32) (s32vector->cpointer out-vec)]
                          [(i64) (s64vector->cpointer out-vec)])])
          (values (append c-params (list _pointer))
                  (append marshalled-args (list out-ptr))
                  out-vec))
        (values c-params marshalled-args #f)))

  (define c-ret (if has-vec-return? _void (ir-type->ctype ret-type decls)))

  ;; Cast address to callable function pointer and invoke
  (define fn-ptr (cast addr _uint64 _pointer))
  (cond
    [has-vec-return?
     ;; Wrapper is void-returning; result is in result-vec
     (define callable (cast fn-ptr _pointer (_cprocedure all-c-params _void)))
     (apply callable all-marshalled-args)
     result-vec]
    [(and (prim-type? ret-type) (eq? (prim-type-tag ret-type) 'void))
     ;; Void return — call for side effect, return Racket (void)
     (define callable (cast fn-ptr _pointer (_cprocedure c-params _void)))
     (apply callable marshalled-args)
     (void)]
    [else
     (define callable (cast fn-ptr _pointer (_cprocedure c-params c-ret)))
     (define raw-result (apply callable marshalled-args))
     (unmarshal-result raw-result ret-type decls registry)]))

;; ---- Disassembly -----------------------------------------------------------

;; Disassemble a JIT'd function and return a string of assembly instructions.
;; Walks the machine code starting at the function's address, decoding
;; instructions until a ret is found or max-bytes is reached.
(define (disassemble m fn-name [max-bytes 4096])
  (define jit (safe-module-jit m))
  ;; Look up the function — use the wrapper if one exists
  (define entry (assq fn-name (safe-module-func-env m)))
  (unless entry
    (error 'disassemble "unknown function: ~a" fn-name))
  (define param-types (car (cdr entry)))
  (define ret-type (cadr (cdr entry)))
  (define needs-wrapper? (or (ormap vec-type? param-types) (vec-type? ret-type)))
  (define lookup-name
    (if needs-wrapper?
        (string-append (symbol->string fn-name) "__wrapper")
        (symbol->string fn-name)))
  (define addr (LLVM-Orc-LLJIT-Lookup jit lookup-name))
  (define base-ptr (cast addr _uint64 _pointer))

  ;; Create disassembler for the host triple
  (define triple-ptr (LLVM-Get-Default-Target-Triple))
  (define triple (cast triple-ptr _pointer _string))
  (LLVM-Dispose-Message triple-ptr)
  (define dc (LLVM-Create-Disasm triple))
  (LLVM-Set-Disasm-Options dc 2)  ; PrintImmHex

  ;; Walk instructions
  (define lines
    (let loop ([offset 0] [acc '()])
      (cond
        [(>= offset max-bytes) (reverse acc)]
        [else
         (define remaining (- max-bytes offset))
         (define pc (+ addr offset))
         (define ptr (ptr-add base-ptr offset))
         (define-values (instr consumed)
           (LLVM-Disasm-Instruction dc ptr remaining pc))
         (cond
           [(not instr) (reverse acc)]
           [else
            (define line (format "  0x~x:\t~a" pc (string-trim instr)))
            (if (regexp-match? #rx"ret" instr)
                (reverse (cons line acc))
                (loop (+ offset consumed) (cons line acc)))])])))

  (string-join lines "\n"))

;; ---- Type marshalling ------------------------------------------------------

(define (ir-type->ctype t decls)
  (cond
    [(prim-type? t)
     (case (prim-type-tag t)
       [(i1)   _bool]
       [(i8)   _int8]
       [(i16)  _int16]
       [(i32)  _int32]
       [(i64)  _int64]
       [(f32)  _float]
       [(f64)  _double]
       [(void) _void]
       [else (error 'ir-type->ctype "unsupported prim: ~a" t)])]
    [(vec-type? t)
     ;; Vectors are passed via pointer (wrapper loads them)
     _pointer]
    [(type-ref? t)
     ;; Records and unions are passed as pointers
     _pointer]
    [else (error 'ir-type->ctype "unsupported type: ~a" t)]))

;; Marshal a single argument. Primitives pass through; records/unions
;; are allocated as C structs and a pointer is returned.
;; If a type-registry entry exists for the type, use struct accessors
;; to extract field values. Otherwise, fall back to list-based marshalling.
(define (marshal-arg arg ir-type decls [registry (hash)])
  (cond
    [(prim-type? ir-type) arg]  ; primitives pass through
    [(vec-type? ir-type)
     ;; Convert ffi/vector to pointer for the wrapper function
     (define elem (vec-type-element ir-type))
     (define tag (prim-type-tag elem))
     (cond
       [(and (eq? tag 'f64) (f64vector? arg)) (f64vector->cpointer arg)]
       [(and (eq? tag 'f32) (f32vector? arg)) (f32vector->cpointer arg)]
       [(and (eq? tag 'i32) (s32vector? arg)) (s32vector->cpointer arg)]
       [(and (eq? tag 'i64) (s64vector? arg)) (s64vector->cpointer arg)]
       [else (error 'marshal "expected ffi/vector for ~a, got ~a" ir-type arg)])]
    [(type-ref? ir-type)
     (define name (type-ref-name ir-type))
     ;; Find the declaration
     (define rec-decl (for/or ([d (in-list decls)])
                        (and (rec? d) (eq? (rec-name d) name) d)))
     (define sum-decl (for/or ([d (in-list decls)])
                        (and (sum? d) (eq? (sum-name d) name) d)))
     ;; Check registry for struct-based marshalling
     (define reg-entry (hash-ref registry name #f))
     (cond
       ;; Struct-based: use registry if arg matches the struct predicate
       [(and rec-decl reg-entry (eq? (car reg-entry) 'record)
             ((caddr reg-entry) arg))
        (marshal-record-struct arg rec-decl reg-entry)]
       [(and sum-decl reg-entry (eq? (car reg-entry) 'union)
             (for/or ([ve (in-list (cadr reg-entry))])
               ((caddr ve) arg)))
        (marshal-union-struct arg sum-decl reg-entry)]
       ;; Fallback to list-based marshalling
       [rec-decl (marshal-record arg rec-decl)]
       [sum-decl (marshal-union arg sum-decl)]
       [else (error 'marshal "unknown type: ~a" name)])]
    [else arg]))

;; Marshal a Racket list to a C struct pointer.
;; arg = (list val1 val2 ...) matching field order.
(define (marshal-record arg rec-decl)
  (define fields (rec-fields rec-decl))
  (define n (length fields))
  (unless (and (list? arg) (= (length arg) n))
    (error 'marshal "record ~a expects ~a fields, got ~a"
           (rec-name rec-decl) n arg))
  ;; Compute struct size: sum of field sizes (simplified alignment)
  ;; Allocate memory and write fields
  (define field-types (map field-type fields))
  (define c-types (map (lambda (t) (ir-type->ctype t '())) field-types))
  (define offsets (compute-offsets c-types))
  (define total-size (+ (last offsets) (ctype-sizeof (last c-types))))
  (define ptr (malloc total-size 'atomic))
  (for ([val (in-list arg)]
        [ct (in-list c-types)]
        [off (in-list offsets)])
    (ptr-set! (ptr-add ptr off) ct val))
  ptr)

;; Marshal a Racket tagged list to a C union pointer.
;; arg = (list 'VariantName val ...) or (list 'VariantName).
(define (marshal-union arg sum-decl)
  (unless (and (list? arg) (pair? arg) (symbol? (car arg)))
    (error 'marshal "union ~a expects (list 'Variant vals ...), got ~a"
           (sum-name sum-decl) arg))
  (define vname (car arg))
  (define vals (cdr arg))
  (define variants (sum-variants sum-decl))
  ;; Find variant index
  (define vi
    (for/or ([v (in-list variants)] [i (in-naturals)])
      (and (eq? (variant-name v) vname) (cons i v))))
  (unless vi
    (error 'marshal "unknown variant ~a in ~a" vname (sum-name sum-decl)))
  (define tag (car vi))
  (define vdecl (cdr vi))
  (define vfields (variant-fields vdecl))
  ;; Allocate: { i32 tag, payload... }
  ;; Use 40 bytes (4 for tag + 32 for payload — matches compile.rkt layout)
  (define ptr (malloc 40 'atomic))
  (memset ptr 0 40)
  ;; Write tag at offset 0
  (ptr-set! ptr _int32 tag)
  ;; Write payload fields starting at offset 8 (aligned to i64)
  (define field-types (map field-type vfields))
  (define c-types (map (lambda (t) (ir-type->ctype t '())) field-types))
  (define payload-ptr (ptr-add ptr 8))
  (define payload-offsets (compute-offsets c-types))
  (for ([val (in-list vals)]
        [ct (in-list c-types)]
        [off (in-list payload-offsets)])
    (ptr-set! (ptr-add payload-ptr off) ct val))
  ptr)

;; ---- Return value unmarshalling ---------------------------------------------

(define (unmarshal-result raw ret-type decls registry)
  (cond
    [(prim-type? ret-type) raw]  ; primitives pass through
    [(type-ref? ret-type)
     (define name (type-ref-name ret-type))
     (define reg-entry (hash-ref registry name #f))
     (define rec-decl (for/or ([d (in-list decls)])
                        (and (rec? d) (eq? (rec-name d) name) d)))
     (define sum-decl (for/or ([d (in-list decls)])
                        (and (sum? d) (eq? (sum-name d) name) d)))
     ;; If name is a variant name (not found as rec or sum directly),
     ;; look up the parent sum type.
     (define-values (actual-sum-decl actual-reg-entry)
       (if sum-decl
           (values sum-decl reg-entry)
           ;; Search for a sum that contains this variant
           (let ([parent (for/or ([d (in-list decls)])
                           (and (sum? d)
                                (for/or ([v (in-list (sum-variants d))])
                                  (and (eq? (variant-name v) name) d))))])
             (if parent
                 (values parent (hash-ref registry (sum-name parent) #f))
                 (values #f #f)))))
     (cond
       [(and rec-decl reg-entry (eq? (car reg-entry) 'record))
        (unmarshal-record-struct raw rec-decl reg-entry)]
       [(and actual-sum-decl actual-reg-entry (eq? (car actual-reg-entry) 'union))
        (unmarshal-union-struct raw actual-sum-decl actual-reg-entry)]
       ;; Fallback: return raw pointer (backward compat)
       [else raw])]
    [else raw]))

;; Read C struct fields and construct Racket struct.
;; reg-entry: (list 'record pred? (list accessor ...))
;; We need the constructor, which is the struct name itself.
;; The registry stores pred? and accessors. We need to also store the constructor.
;; Let's change the registry format to include it:
;;   (list 'record constructor pred? (list accessor ...))
;; For now, derive constructor from pred? name... actually, let's update
;; the registry format. It's simpler to store the constructor directly.

;; Updated format: (list 'record constructor pred? (list accessor ...))
(define (unmarshal-record-struct ptr rec-decl reg-entry)
  (define constructor (cadr reg-entry))
  (define fields (rec-fields rec-decl))
  (define field-types (map field-type fields))
  (define c-types (map (lambda (t) (ir-type->ctype t '())) field-types))
  (define offsets (compute-offsets c-types))
  (define vals
    (for/list ([ct (in-list c-types)]
               [off (in-list offsets)])
      (ptr-ref (ptr-add ptr off) ct)))
  (apply constructor vals))

;; Read tag, dispatch to variant, construct variant struct.
;; reg-entry: (list 'union (list (list 'VName constructor pred? (list acc ...)) ...))
(define (unmarshal-union-struct ptr sum-decl reg-entry)
  (define variant-entries (cadr reg-entry))
  (define tag (ptr-ref ptr _int32))
  (define variants (sum-variants sum-decl))
  ;; Find variant by tag index
  (define vi
    (for/or ([v (in-list variants)] [i (in-naturals)])
      (and (= i tag) v)))
  (unless vi
    (error 'unmarshal "unknown tag ~a for ~a" tag (sum-name sum-decl)))
  ;; Find matching registry entry
  (define vname (variant-name vi))
  (define ve (for/or ([e (in-list variant-entries)])
               (and (eq? (car e) vname) e)))
  (unless ve
    (error 'unmarshal "no registry entry for variant ~a" vname))
  (define constructor (cadr ve))
  (define vfields (variant-fields vi))
  (if (null? vfields)
      (constructor)
      (let* ([field-types (map field-type vfields)]
             [c-types (map (lambda (t) (ir-type->ctype t '())) field-types)]
             [payload-ptr (ptr-add ptr 8)]  ; payload starts after tag (aligned to i64)
             [offsets (compute-offsets c-types)]
             [vals (for/list ([ct (in-list c-types)]
                              [off (in-list offsets)])
                     (ptr-ref (ptr-add payload-ptr off) ct))])
        (apply constructor vals))))

;; ---- Struct-based marshalling ------------------------------------------------
;; When a type registry provides Racket struct accessors, use them to
;; extract field values from struct instances.

;; Registry entry for record: (list 'record constructor pred? (list accessor ...))
(define (marshal-record-struct arg rec-decl reg-entry)
  (define pred? (caddr reg-entry))
  (define accessors (cadddr reg-entry))
  (unless (pred? arg)
    (error 'marshal "expected ~a struct instance, got ~a"
           (rec-name rec-decl) arg))
  ;; Extract field values using accessors
  (define vals (map (lambda (acc) (acc arg)) accessors))
  ;; Delegate to existing record marshalling with the extracted list
  (marshal-record vals rec-decl))

;; Registry entry for union: (list 'union (list (list 'VName ctor pred? (list acc ...)) ...))
(define (marshal-union-struct arg sum-decl reg-entry)
  (define variant-entries (cadr reg-entry))
  ;; Find which variant matches
  (define match-entry
    (for/or ([ve (in-list variant-entries)])
      (and ((caddr ve) arg) ve)))
  (unless match-entry
    (error 'marshal "value does not match any variant of ~a: ~a"
           (sum-name sum-decl) arg))
  (define vname (car match-entry))
  (define accessors (cadddr match-entry))
  (define vals (map (lambda (acc) (acc arg)) accessors))
  ;; Delegate to existing union marshalling with tagged list
  (marshal-union (cons vname vals) sum-decl))

;; Compute byte offsets for a list of ctypes (sequential, naturally aligned).
(define (compute-offsets c-types)
  (let loop ([remaining c-types] [offset 0] [acc '()])
    (if (null? remaining)
        (reverse acc)
        (let* ([ct (car remaining)]
               [size (ctype-sizeof ct)]
               [align size]  ; natural alignment
               [aligned-off (+ offset (modulo (- align (modulo offset align)) align))])
          (loop (cdr remaining) (+ aligned-off size) (cons aligned-off acc))))))
