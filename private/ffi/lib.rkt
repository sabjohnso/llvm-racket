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
         allocator/prevent-gc)

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

