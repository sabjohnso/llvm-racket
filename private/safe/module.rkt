#lang racket/base

(require ffi/unsafe
         racket/list
         "repr.rkt"
         "type-check.rkt"
         "compile.rkt"
         "../ffi/lib.rkt"
         "../ffi/types.rkt"
         "../ffi/core.rkt"
         "../ffi/target.rkt"
         "../ffi/target-machine.rkt"
         "../ffi/passes.rkt"
         "../ffi/orc.rkt")

(provide make-llvm-module
         call
         safe-module?
         safe-module-ir)

;; ---- Safe module -----------------------------------------------------------

(struct safe-module (jit func-env ir decls) #:transparent)

;; ---- make-llvm-module ------------------------------------------------------

(define (make-llvm-module #:optimize [optimize "default<O2>"] . decls)
  (Initialize-Native-Target!)

  ;; Compile to LLVM IR
  (define cm (compile-module decls))
  (define llvm-mod (compiled-module-llvm-module cm))
  (define ctx (compiled-module-context cm))
  (define ir (compiled-module-ir cm))

  ;; Optimize (unless #f)
  (define triple-ptr (LLVM-Get-Default-Target-Triple))
  (define triple (cast triple-ptr _pointer _string))
  (LLVM-Dispose-Message triple-ptr)
  (define target (LLVM-Get-Target-From-Triple triple))
  (define tm (LLVM-Create-Target-Machine
              target triple "generic" ""
              'LLVMCodeGenLevelDefault
              'LLVMRelocDefault
              'LLVMCodeModelDefault))
  (when optimize
    (define popts (LLVM-Create-Pass-Builder-Options))
    (LLVM-Run-Passes llvm-mod optimize tm popts))

  ;; Create a fresh JIT per module to avoid symbol conflicts
  (define jit (LLVM-Orc-Create-LLJIT #f))

  ;; Wrap in thread-safe module and add to JIT
  (define ts-ctx (LLVM-Orc-Create-New-Thread-Safe-Context))
  (define ts-mod (LLVM-Orc-Create-New-Thread-Safe-Module llvm-mod ts-ctx))
  (define dylib (LLVM-Orc-LLJIT-Get-Main-JIT-Dylib jit))
  (LLVM-Orc-LLJIT-Add-LLVM-IR-Module jit dylib ts-mod)

  ;; Build func-env for call dispatch (with return types)
  (define func-env
    (let loop ([remaining (filter func? decls)] [env '()])
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

  (safe-module jit func-env ir decls))

;; ---- call ------------------------------------------------------------------

(define (call m fn-name . args)
  (define jit (safe-module-jit m))
  (define entry (assq fn-name (safe-module-func-env m)))
  (unless entry
    (error 'call "unknown function: ~a" fn-name))
  (define param-types (car (cdr entry)))
  (define ret-type (cadr (cdr entry)))
  (define decls (safe-module-decls m))

  ;; Look up the function address
  (define addr (LLVM-Orc-LLJIT-Lookup jit (symbol->string fn-name)))

  ;; Marshal arguments: convert Racket values to C values.
  ;; type-ref args get marshalled to heap-allocated struct pointers.
  (define c-params (map (lambda (t) (ir-type->ctype t decls)) param-types))
  (define c-ret (ir-type->ctype ret-type decls))
  (define marshalled-args
    (map (lambda (arg t) (marshal-arg arg t decls)) args param-types))

  ;; Cast address to callable function pointer and invoke
  (define fn-ptr (cast addr _uint64 _pointer))
  (cond
    [(and (prim-type? ret-type) (eq? (prim-type-tag ret-type) 'void))
     ;; Void return — call for side effect, return Racket (void)
     (define callable (cast fn-ptr _pointer (_cprocedure c-params _void)))
     (apply callable marshalled-args)
     (void)]
    [else
     (define callable (cast fn-ptr _pointer (_cprocedure c-params c-ret)))
     (apply callable marshalled-args)]))

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
    [(type-ref? t)
     ;; Records and unions are passed as pointers
     _pointer]
    [else (error 'ir-type->ctype "unsupported type: ~a" t)]))

;; Marshal a single argument. Primitives pass through; records/unions
;; are allocated as C structs and a pointer is returned.
(define (marshal-arg arg ir-type decls)
  (cond
    [(prim-type? ir-type) arg]  ; primitives pass through
    [(type-ref? ir-type)
     (define name (type-ref-name ir-type))
     ;; Find the declaration
     (define rec-decl (for/or ([d (in-list decls)])
                        (and (rec? d) (eq? (rec-name d) name) d)))
     (define sum-decl (for/or ([d (in-list decls)])
                        (and (sum? d) (eq? (sum-name d) name) d)))
     (cond
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
