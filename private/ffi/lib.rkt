#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define
         ffi/unsafe/alloc
         (for-syntax racket/base
                     racket/string))

(provide llvm-lib
         define-llvm
         kebab->pascal
         prevent-gc!
         prevent-gc-wrap
         allocator/prevent-gc
         make-register-allocation
         check-llvm-error
         check-llvm-error-ref
         consume-llvm-error-ref)

;; Try to load libLLVM from a specific directory with version fallback.
(define (try-load-from dir)
  (define versions '("20" "19" "18" "17" "16" "15" ""))
  (for/or ([v (in-list versions)])
    (with-handlers ([exn:fail? (λ (_) #f)])
      (ffi-lib (build-path dir (string-append "libLLVM-" v))))))

;; Well-known LLVM installation directories.
(define search-dirs
  (append
   ;; Debian/Ubuntu versioned paths
   (for/list ([v (in-range 20 14 -1)])
     (format "/usr/lib/llvm-~a/lib" v))
   (list "/usr/lib"
         "/usr/lib64"
         "/usr/local/lib")))

;; Load libLLVM shared library.
;; Priority: LLVM_LIB_PATH env var > default search > known directories.
(define llvm-lib
  (or
   ;; 1. Explicit path from env var
   (let ([custom-path (getenv "LLVM_LIB_PATH")])
     (and custom-path (ffi-lib custom-path)))
   ;; 2. Default system library search
   (with-handlers ([exn:fail? (λ (_) #f)])
     (ffi-lib "libLLVM" '("20" "19" "18" "17" "16" "15" "")))
   ;; 3. Search well-known directories
   (for/or ([dir (in-list search-dirs)])
     (and (directory-exists? dir) (try-load-from dir)))
   ;; 4. Give up
   (error 'llvm-lib "could not find libLLVM shared library")))

;; Naming convention: LLVM-Context-Create → LLVMContextCreate
;; Bound via define-syntax so define-ffi-definer can retrieve it
;; with syntax-local-value at macro expansion time.
(define-syntax kebab->pascal
  (lambda (stx)
    (datum->syntax stx
      (string->symbol
       (string-replace (symbol->string (syntax-e stx)) "-" "")))))

(define-ffi-definer define-llvm llvm-lib
  #:make-c-id kebab->pascal)

;; Prevent-GC: weak-key hash table that keeps parent resources alive
;; as long as the dependent resource is reachable.
;;
;; Example: a module depends on its context. Anchoring the context to
;; the module ensures the GC won't finalize the context while the
;; module is still in use.
(define prevent-gc-table (make-weak-hasheq))

(define (prevent-gc! dependent parent)
  (hash-update! prevent-gc-table dependent
                (lambda (existing) (cons parent existing))
                '()))

;; Wrap a foreign function so its return value is anchored to one or
;; more of its arguments.  parent-arg-indices are 0-based positions
;; in the Racket-side argument list.
(define (prevent-gc-wrap . parent-arg-indices)
  (lambda (proc)
    (lambda args
      (define result (apply proc args))
      (when result
        (for ([idx (in-list parent-arg-indices)])
          (prevent-gc! result (list-ref args idx))))
      result)))

;; Register a resource returned via out-parameter with the
;; allocator/deallocator finalization mechanism.  Returns a function
;; that takes a resource and returns it, with a GC finalizer attached.
;; Explicit calls to the corresponding deallocator cancel the finalizer.
(define (make-register-allocation dealloc)
  ((allocator dealloc) (lambda (v) v)))

;; Compose (allocator dealloc) with prevent-gc! anchoring.
;; parent-arg-indices are 0-based positions in the Racket-side argument
;; list; each referenced argument is anchored to the return value.
(define (allocator/prevent-gc dealloc . parent-arg-indices)
  (define wrap (allocator dealloc))
  (lambda (proc)
    (define wrapped (wrap proc))
    (lambda args
      (define result (apply wrapped args))
      (when result
        (for ([idx (in-list parent-arg-indices)])
          (prevent-gc! result (list-ref args idx))))
      result)))

;; Check an LLVM error return.  If result is non-zero, extract the
;; error message from the pointer, free it, and raise exn:fail.
(define (check-llvm-error who result err-ptr)
  (unless (zero? result)
    (define msg
      (if err-ptr
          (let ([s (cast err-ptr _pointer _string)])
            (LLVMDisposeMessage err-ptr)
            s)
          "unknown LLVM error"))
    (error who "~a" msg)))

;; Raw LLVMDisposeMessage for use in check-llvm-error.
;; We can't use the wrapped LLVM-Dispose-Message from core.rkt
;; (circular dependency), so we bind it directly here.
(define LLVMDisposeMessage
  (get-ffi-obj "LLVMDisposeMessage" llvm-lib
               (_fun _pointer -> _void)))

;; Check an LLVMErrorRef return.  If non-null, extract the error
;; message, free it, and raise exn:fail.  Used by the new pass
;; manager and ORC JIT APIs.
(define LLVMGetErrorMessage
  (get-ffi-obj "LLVMGetErrorMessage" llvm-lib
               (_fun _pointer -> _pointer)))

(define LLVMDisposeErrorMessage
  (get-ffi-obj "LLVMDisposeErrorMessage" llvm-lib
               (_fun _pointer -> _void)))

(define (check-llvm-error-ref who err-ref)
  (when err-ref
    (define msg-ptr (LLVMGetErrorMessage err-ref))
    (define msg (if msg-ptr (cast msg-ptr _pointer _string) "unknown LLVM error"))
    (when msg-ptr (LLVMDisposeErrorMessage msg-ptr))
    (error who "~a" msg)))

;; Silently consume an LLVMErrorRef without raising.
;; Used in GC finalizers where exceptions can't propagate.
(define (consume-llvm-error-ref err-ref)
  (when err-ref
    (define msg-ptr (LLVMGetErrorMessage err-ref))
    (when msg-ptr (LLVMDisposeErrorMessage msg-ptr))))

