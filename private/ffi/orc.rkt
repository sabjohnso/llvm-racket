#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "module.rkt")

(provide ;; Thread-safe context
         LLVM-Orc-Create-New-Thread-Safe-Context
         LLVM-Orc-Dispose-Thread-Safe-Context
         LLVM-Orc-Thread-Safe-Context-Get-Context
         ;; Thread-safe module
         LLVM-Orc-Create-New-Thread-Safe-Module
         LLVM-Orc-Dispose-Thread-Safe-Module
         ;; LLJIT
         LLVM-Orc-Create-LLJIT
         LLVM-Orc-Dispose-LLJIT
         LLVM-Orc-LLJIT-Get-Main-JIT-Dylib
         LLVM-Orc-LLJIT-Get-Execution-Session
         LLVM-Orc-LLJIT-Get-Triple-String
         LLVM-Orc-LLJIT-Add-LLVM-IR-Module
         LLVM-Orc-LLJIT-Lookup
         ;; Process symbol resolution
         LLVM-Orc-LLJIT-Get-Global-Prefix
         LLVM-Orc-Create-Dynamic-Library-Search-Generator-For-Process
         LLVM-Orc-JIT-Dylib-Add-Generator)

;; ---- Thread-Safe Context ---------------------------------------------------

(define-llvm LLVM-Orc-Dispose-Thread-Safe-Context
  (_fun _LLVM-Orc-Thread-Safe-Context-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Orc-Create-New-Thread-Safe-Context
  (_fun -> _LLVM-Orc-Thread-Safe-Context-Ref)
  #:wrap (allocator LLVM-Orc-Dispose-Thread-Safe-Context))

;; Get the underlying LLVMContextRef.  The context is owned by the
;; thread-safe context — do not dispose it separately.
(define-llvm LLVM-Orc-Thread-Safe-Context-Get-Context
  (_fun _LLVM-Orc-Thread-Safe-Context-Ref -> _LLVM-Context-Ref)
  #:wrap (prevent-gc-wrap 0))

;; ---- Thread-Safe Module ----------------------------------------------------
;; Takes ownership of the module.  Cancel the module's GC finalizer.

(define-llvm LLVM-Orc-Dispose-Thread-Safe-Module
  (_fun _LLVM-Orc-Thread-Safe-Module-Ref -> _void)
  #:wrap (deallocator))

;; Cancel the ts-module's GC finalizer without freeing it.
;; Used when ownership transfers to LLJIT via Add-LLVM-IR-Module.
(define cancel-ts-module-ownership!
  ((deallocator) (lambda (_tsm) (void))))

(define-llvm LLVM-Orc-Create-New-Thread-Safe-Module
  (_fun _LLVM-Module-Ref _LLVM-Orc-Thread-Safe-Context-Ref
        -> _LLVM-Orc-Thread-Safe-Module-Ref)
  #:wrap (let ()
           (define wrap (allocator LLVM-Orc-Dispose-Thread-Safe-Module))
           (lambda (proc)
             (define wrapped (wrap proc))
             (lambda (mod ts-ctx)
               (define result (wrapped mod ts-ctx))
               (when result
                 ;; Module ownership transfers — cancel its finalizer.
                 (cancel-module-ownership! mod)
                 ;; Anchor ts-module to ts-ctx so it stays alive.
                 (prevent-gc! result ts-ctx))
               result))))

;; ---- LLJIT -----------------------------------------------------------------
;; LLVMOrcCreateLLJIT returns LLVMErrorRef with out-param.
;; LLVMOrcDisposeLLJIT also returns LLVMErrorRef (can fail).

;; Raw dispose — returns LLVMErrorRef.
(define LLVMOrcDisposeLLJIT-raw
  (get-ffi-obj "LLVMOrcDisposeLLJIT" llvm-lib
               (_fun _LLVM-Orc-LLJIT-Ref -> _pointer)))

(define (LLVM-Orc-Dispose-LLJIT jit)
  (define err (LLVMOrcDisposeLLJIT-raw jit))
  (check-llvm-error-ref 'LLVM-Orc-Dispose-LLJIT err))

;; For GC finalization, silently consume errors (can't raise from finalizer).
(define (dispose-lljit-silent jit)
  (define err (LLVMOrcDisposeLLJIT-raw jit))
  (when err (consume-llvm-error-ref err)))

(define register-lljit!
  (make-register-allocation ((deallocator) dispose-lljit-silent)))

;; LLVMOrcCreateLLJIT(LLVMOrcLLJITRef *Result, LLVMOrcLLJITBuilderRef Builder)
;; Builder can be NULL for defaults.
(define-llvm LLVM-Orc-Create-LLJIT
  (_fun (jit : (_ptr o _LLVM-Orc-LLJIT-Ref))
        _pointer                          ; builder (NULL = defaults)
        -> (err : _pointer)               ; LLVMErrorRef
        -> (values err jit))
  #:wrap (let ()
           (lambda (proc)
             (lambda (builder)
               (define-values (err jit) (proc (or builder #f)))
               (check-llvm-error-ref 'LLVM-Orc-Create-LLJIT err)
               (register-lljit! jit)
               jit))))

;; ---- LLJIT Accessors -------------------------------------------------------

(define-llvm LLVM-Orc-LLJIT-Get-Main-JIT-Dylib
  (_fun _LLVM-Orc-LLJIT-Ref -> _LLVM-Orc-JIT-Dylib-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Orc-LLJIT-Get-Execution-Session
  (_fun _LLVM-Orc-LLJIT-Ref -> _LLVM-Orc-Execution-Session-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Orc-LLJIT-Get-Triple-String
  (_fun _LLVM-Orc-LLJIT-Ref -> _string))

;; ---- Add Module / Lookup ---------------------------------------------------

;; Adds a thread-safe module to a JITDylib.  Takes ownership of TSM.
(define-llvm LLVM-Orc-LLJIT-Add-LLVM-IR-Module
  (_fun _LLVM-Orc-LLJIT-Ref
        _LLVM-Orc-JIT-Dylib-Ref
        _LLVM-Orc-Thread-Safe-Module-Ref
        -> _pointer)                      ; LLVMErrorRef
  #:wrap (let ()
           (lambda (proc)
             (lambda (jit dylib ts-mod)
               (define err (proc jit dylib ts-mod))
               (check-llvm-error-ref 'LLVM-Orc-LLJIT-Add-LLVM-IR-Module err)
               ;; LLJIT now owns the ts-module — cancel its finalizer.
               (cancel-ts-module-ownership! ts-mod)))))

;; Lookup a symbol.  Returns its address as uint64.
(define-llvm LLVM-Orc-LLJIT-Lookup
  (_fun _LLVM-Orc-LLJIT-Ref
        (addr : (_ptr o _uint64))
        _string
        -> (err : _pointer)
        -> (values err addr))
  #:wrap (let ()
           (lambda (proc)
             (lambda (jit name)
               (define-values (err addr) (proc jit name))
               (check-llvm-error-ref 'LLVM-Orc-LLJIT-Lookup err)
               addr))))

;; ---- Process Symbol Resolution -----------------------------------------------
;; Allow the JIT to find symbols from the host process (e.g., libm functions).

(define-llvm LLVM-Orc-LLJIT-Get-Global-Prefix
  (_fun _LLVM-Orc-LLJIT-Ref -> _byte))

;; LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(
;;   LLVMOrcDefinitionGeneratorRef *Result,
;;   char GlobalPrefix, void *Filter, void *FilterCtx)
;; → LLVMErrorRef
(define-llvm LLVM-Orc-Create-Dynamic-Library-Search-Generator-For-Process
  (_fun (gen : (_ptr o _LLVM-Orc-Definition-Generator-Ref))
        _byte       ; global prefix
        _pointer    ; filter (NULL = accept all)
        _pointer    ; filter ctx (NULL)
        -> (err : _pointer)
        -> (values err gen))
  #:wrap (let ()
           (lambda (proc)
             (lambda (prefix)
               (define-values (err gen) (proc prefix #f #f))
               (check-llvm-error-ref
                'LLVM-Orc-Create-Dynamic-Library-Search-Generator-For-Process err)
               gen))))

;; LLVMOrcJITDylibAddGenerator(LLVMOrcJITDylibRef, LLVMOrcDefinitionGeneratorRef)
;; Transfers ownership of the generator to the dylib.
(define-llvm LLVM-Orc-JIT-Dylib-Add-Generator
  (_fun _LLVM-Orc-JIT-Dylib-Ref
        _LLVM-Orc-Definition-Generator-Ref
        -> _void))
