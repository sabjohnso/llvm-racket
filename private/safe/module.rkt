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

(struct safe-module (jit func-env ir) #:transparent)

;; ---- make-llvm-module ------------------------------------------------------

(define (make-llvm-module . decls)
  (Initialize-Native-Target!)

  ;; Compile to LLVM IR
  (define cm (compile-module decls))
  (define llvm-mod (compiled-module-llvm-module cm))
  (define ctx (compiled-module-context cm))
  (define ir (compiled-module-ir cm))

  ;; Optimize
  (define triple-ptr (LLVM-Get-Default-Target-Triple))
  (define triple (cast triple-ptr _pointer _string))
  (LLVM-Dispose-Message triple-ptr)
  (define target (LLVM-Get-Target-From-Triple triple))
  (define tm (LLVM-Create-Target-Machine
              target triple "generic" ""
              'LLVMCodeGenLevelDefault
              'LLVMRelocDefault
              'LLVMCodeModelDefault))
  (define popts (LLVM-Create-Pass-Builder-Options))
  (LLVM-Run-Passes llvm-mod "default<O2>" tm popts)

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

  (safe-module jit func-env ir))

;; ---- call ------------------------------------------------------------------

(define (call m fn-name . args)
  (define jit (safe-module-jit m))
  (define entry (assq fn-name (safe-module-func-env m)))
  (unless entry
    (error 'call "unknown function: ~a" fn-name))
  (define param-types (car (cdr entry)))
  (define ret-type (cadr (cdr entry)))

  ;; Look up the function address
  (define addr (LLVM-Orc-LLJIT-Lookup jit (symbol->string fn-name)))

  ;; Build FFI types
  (define c-params (map ir-type->ctype param-types))
  (define c-ret (ir-type->ctype ret-type))

  ;; Cast address to callable function pointer and invoke
  (define fn-ptr (cast addr _uint64 _pointer))
  (define callable (cast fn-ptr _pointer (_cprocedure c-params c-ret)))
  (apply callable args))

;; ---- Type marshalling ------------------------------------------------------

(define (ir-type->ctype t)
  (define tag (prim-type-tag t))
  (case tag
    [(i1)   _bool]
    [(i8)   _int8]
    [(i16)  _int16]
    [(i32)  _int32]
    [(i64)  _int64]
    [(f32)  _float]
    [(f64)  _double]
    [else (error 'ir-type->ctype "unsupported type: ~a" t)]))
