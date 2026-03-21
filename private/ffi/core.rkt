#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide LLVM-Context-Create
         LLVM-Context-Dispose
         LLVM-Module-Create-With-Name-In-Context
         LLVM-Dispose-Module
         cancel-module-ownership!
         LLVM-Int32-Type-In-Context
         LLVM-Function-Type
         LLVM-Add-Function
         LLVM-Get-Param
         LLVM-Append-Basic-Block-In-Context
         LLVM-Create-Builder-In-Context
         LLVM-Position-Builder-At-End
         LLVM-Build-Add
         LLVM-Build-Ret
         LLVM-Dispose-Builder
         LLVM-Print-Module-To-String
         LLVM-Dispose-Message
         LLVM-Get-Buffer-Start
         LLVM-Get-Buffer-Size
         LLVM-Dispose-Memory-Buffer)

;; Context
(define-llvm LLVM-Context-Dispose
  (_fun _LLVM-Context-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Context-Create
  (_fun -> _LLVM-Context-Ref)
  #:wrap (allocator LLVM-Context-Dispose))

;; Module — ownership can transfer to an execution engine.
;; Marked as allocator/deallocator for the standalone case.
;; When ownership transfers (e.g., to MCJIT), call
;; cancel-module-ownership! to cancel the finalizer without
;; freeing the module.
(define-llvm LLVM-Dispose-Module
  (_fun _LLVM-Module-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Module-Create-With-Name-In-Context
  (_fun _string _LLVM-Context-Ref -> _LLVM-Module-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Module 1))

;; Cancel the module's GC finalizer without freeing it.
;; Used when ownership transfers to an execution engine.
(define cancel-module-ownership!
  ((deallocator) (lambda (_mod) (void))))

;; Types — handles into the context, not separately allocated.
;; Anchor to context so it can't be GC'd while type ref is held.
(define-llvm LLVM-Int32-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (ctx)
               (define ty (proc ctx))
               (when ty (prevent-gc! ty ctx))
               ty))))

(define-llvm LLVM-Function-Type
  (_fun _LLVM-Type-Ref              ; return type
        (_list i _LLVM-Type-Ref)    ; param types
        _uint                       ; param count
        _LLVM-Bool                  ; is-vararg
        -> _LLVM-Type-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (ret-type param-types count vararg?)
               (define ty (proc ret-type param-types count vararg?))
               ;; Anchor to the return type — transitively keeps context alive.
               (when ty (prevent-gc! ty ret-type))
               ty))))

;; Functions — handles into the module.
;; Anchor to module so it can't be GC'd while function ref is held.
(define-llvm LLVM-Add-Function
  (_fun _LLVM-Module-Ref _string _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod name type)
               (define fn (proc mod name type))
               (when fn (prevent-gc! fn mod))
               fn))))

;; Params — handles into the function (and transitively the module).
;; Anchor to the function so the module can't be GC'd.
(define-llvm LLVM-Get-Param
  (_fun _LLVM-Value-Ref _uint -> _LLVM-Value-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (fn index)
               (define param (proc fn index))
               (when param (prevent-gc! param fn))
               param))))

;; Basic blocks — handles into the function.
;; Anchor to the function so the module can't be GC'd.
(define-llvm LLVM-Append-Basic-Block-In-Context
  (_fun _LLVM-Context-Ref _LLVM-Value-Ref _string -> _LLVM-Basic-Block-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (ctx fn name)
               (define bb (proc ctx fn name))
               (when bb (prevent-gc! bb fn))
               bb))))

;; Builder — tracks which basic block it's positioned at so that
;; instructions can be anchored to it.
(define-llvm LLVM-Dispose-Builder
  (_fun _LLVM-Builder-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Builder-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Builder-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Builder 0))

;; Track the basic block each builder is positioned at.
;; Instructions built via the builder live in that block's function's module.
(define builder-current-bb (make-weak-hasheq))

(define-llvm LLVM-Position-Builder-At-End
  (_fun _LLVM-Builder-Ref _LLVM-Basic-Block-Ref -> _void)
  #:wrap (let ()
           (lambda (proc)
             (lambda (builder bb)
               (proc builder bb)
               (hash-set! builder-current-bb builder bb)))))

;; Helper: anchor a builder instruction result to the builder's
;; current basic block, preserving the chain result → bb → fn → mod → ctx.
(define (anchor-instruction! result builder)
  (when result
    (define bb (hash-ref builder-current-bb builder #f))
    (when bb (prevent-gc! result bb))))

(define-llvm LLVM-Build-Add
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (builder lhs rhs name)
               (define result (proc builder lhs rhs name))
               (anchor-instruction! result builder)
               result))))

(define-llvm LLVM-Build-Ret
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref -> _LLVM-Value-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (builder val)
               (define result (proc builder val))
               (anchor-instruction! result builder)
               result))))

;; Utility — messages are allocated by LLVM, freed with Dispose-Message.
(define-llvm LLVM-Dispose-Message
  (_fun _pointer -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Print-Module-To-String
  (_fun _LLVM-Module-Ref -> _pointer)
  #:wrap (allocator LLVM-Dispose-Message))

;; Memory buffers
(define-llvm LLVM-Dispose-Memory-Buffer
  (_fun _LLVM-Memory-Buffer-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Get-Buffer-Start
  (_fun _LLVM-Memory-Buffer-Ref -> _pointer))

(define-llvm LLVM-Get-Buffer-Size
  (_fun _LLVM-Memory-Buffer-Ref -> _size))
