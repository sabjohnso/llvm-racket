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
         ;; Integer types
         LLVM-Int1-Type-In-Context
         LLVM-Int8-Type-In-Context
         LLVM-Int16-Type-In-Context
         LLVM-Int32-Type-In-Context
         LLVM-Int64-Type-In-Context
         LLVM-Int-Type-In-Context
         ;; Float types
         LLVM-Float-Type-In-Context
         LLVM-Double-Type-In-Context
         ;; Void and pointer types
         LLVM-Void-Type-In-Context
         LLVM-Pointer-Type-In-Context
         ;; Aggregate types
         LLVM-Struct-Type-In-Context
         LLVM-Struct-Create-Named
         LLVM-Struct-Set-Body
         LLVM-Array-Type
         LLVM-Vector-Type
         ;; Function types
         LLVM-Function-Type
         LLVM-Add-Function
         LLVM-Get-Param
         LLVM-Append-Basic-Block-In-Context
         LLVM-Create-Builder-In-Context
         LLVM-Position-Builder-At-End
         LLVM-Build-Add
         LLVM-Build-Sub
         LLVM-Build-NSWSub
         LLVM-Build-Mul
         LLVM-Build-NSWMul
         LLVM-Build-SDiv
         LLVM-Build-UDiv
         LLVM-Build-SRem
         LLVM-Build-URem
         LLVM-Build-Neg
         LLVM-Build-FAdd
         LLVM-Build-FSub
         LLVM-Build-FMul
         LLVM-Build-FDiv
         LLVM-Build-FNeg
         LLVM-Build-And
         LLVM-Build-Or
         LLVM-Build-Xor
         LLVM-Build-Shl
         LLVM-Build-LShr
         LLVM-Build-AShr
         LLVM-Build-Not
         LLVM-Build-Ret
         LLVM-Build-Ret-Void
         LLVM-Dispose-Builder
         LLVM-Print-Module-To-String
         LLVM-Dispose-Message
         LLVM-Get-Buffer-Start
         LLVM-Get-Buffer-Size
         LLVM-Dispose-Memory-Buffer)

;; ---- Context ---------------------------------------------------------------

(define-llvm LLVM-Context-Dispose
  (_fun _LLVM-Context-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Context-Create
  (_fun -> _LLVM-Context-Ref)
  #:wrap (allocator LLVM-Context-Dispose))

;; ---- Module ----------------------------------------------------------------
;; Ownership can transfer to an execution engine.  When it does, call
;; cancel-module-ownership! to cancel the GC finalizer.

(define-llvm LLVM-Dispose-Module
  (_fun _LLVM-Module-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Module-Create-With-Name-In-Context
  (_fun _string _LLVM-Context-Ref -> _LLVM-Module-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Module 1))

(define cancel-module-ownership!
  ((deallocator) (lambda (_mod) (void))))

;; ---- Types -----------------------------------------------------------------
;; Handles into the context.  Anchor result → context (arg 0).

(define-llvm LLVM-Int1-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int8-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int16-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int32-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int64-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Int-Type-In-Context
  (_fun _LLVM-Context-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Float-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Double-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

(define-llvm LLVM-Void-Type-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Address space 0 = default.
(define-llvm LLVM-Pointer-Type-In-Context
  (_fun _LLVM-Context-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Anonymous struct.  packed = 0 for normal layout.
(define-llvm LLVM-Struct-Type-In-Context
  (_fun _LLVM-Context-Ref
        (_list i _LLVM-Type-Ref)    ; element types
        _uint                       ; element count
        _LLVM-Bool                  ; packed
        -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Named struct (opaque until body is set).
(define-llvm LLVM-Struct-Create-Named
  (_fun _LLVM-Context-Ref _string -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Set the body of a named struct.
(define-llvm LLVM-Struct-Set-Body
  (_fun _LLVM-Type-Ref              ; named struct
        (_list i _LLVM-Type-Ref)    ; element types
        _uint                       ; element count
        _LLVM-Bool                  ; packed
        -> _void))

;; Array type.  LLVMArrayType takes unsigned int count (LLVM 15).
;; Anchor to the element type — transitively keeps context alive.
(define-llvm LLVM-Array-Type
  (_fun _LLVM-Type-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Fixed-length vector type.
;; Anchor to the element type — transitively keeps context alive.
(define-llvm LLVM-Vector-Type
  (_fun _LLVM-Type-Ref _uint -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Anchor to the return type, which transitively keeps context alive.
(define-llvm LLVM-Function-Type
  (_fun _LLVM-Type-Ref              ; return type
        (_list i _LLVM-Type-Ref)    ; param types
        _uint                       ; param count
        _LLVM-Bool                  ; is-vararg
        -> _LLVM-Type-Ref)
  #:wrap (prevent-gc-wrap 0))

;; ---- Functions -------------------------------------------------------------
;; Handles into the module.  Anchor result → module.

(define-llvm LLVM-Add-Function
  (_fun _LLVM-Module-Ref _string _LLVM-Type-Ref -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

;; Params are handles into the function.  Anchor result → function.
(define-llvm LLVM-Get-Param
  (_fun _LLVM-Value-Ref _uint -> _LLVM-Value-Ref)
  #:wrap (prevent-gc-wrap 0))

;; ---- Basic Blocks ----------------------------------------------------------
;; Handles into the function.  Anchor result → function (arg 1).

(define-llvm LLVM-Append-Basic-Block-In-Context
  (_fun _LLVM-Context-Ref _LLVM-Value-Ref _string -> _LLVM-Basic-Block-Ref)
  #:wrap (prevent-gc-wrap 1))

;; ---- Builder ---------------------------------------------------------------

(define-llvm LLVM-Dispose-Builder
  (_fun _LLVM-Builder-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Builder-In-Context
  (_fun _LLVM-Context-Ref -> _LLVM-Builder-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-Builder 0))

;; Track the basic block each builder is positioned at.
;; Instructions live in that block's function's module.
(define builder-current-bb (make-weak-hasheq))

(define-llvm LLVM-Position-Builder-At-End
  (_fun _LLVM-Builder-Ref _LLVM-Basic-Block-Ref -> _void)
  #:wrap (let ()
           (lambda (proc)
             (lambda (builder bb)
               (proc builder bb)
               (hash-set! builder-current-bb builder bb)))))

;; Anchor instruction result → builder's current basic block,
;; preserving the chain: result → bb → fn → mod → ctx.
(define (anchor-instruction! result builder)
  (when result
    (define bb (hash-ref builder-current-bb builder #f))
    (when bb (prevent-gc! result bb))))

(define (instruction-wrap proc)
  (lambda (builder . args)
    (define result (apply proc builder args))
    (anchor-instruction! result builder)
    result))

;; Binary arithmetic: (builder, lhs, rhs, name) -> value
(define _build-binop
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref))

;; Unary arithmetic: (builder, val, name) -> value
(define _build-unop
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref))

(define-llvm LLVM-Build-Add    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Sub    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-NSWSub _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Mul    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-NSWMul _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-UDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SRem   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-URem   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FAdd   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FSub   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FMul   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Neg    _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FNeg   _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))

;; Bitwise
(define-llvm LLVM-Build-And    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Or     _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Xor    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Shl    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-LShr   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-AShr   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Not    _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Ret
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Ret-Void
  (_fun _LLVM-Builder-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Utility ---------------------------------------------------------------

(define-llvm LLVM-Dispose-Message
  (_fun _pointer -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Print-Module-To-String
  (_fun _LLVM-Module-Ref -> _pointer)
  #:wrap (allocator LLVM-Dispose-Message))

;; ---- Memory Buffers --------------------------------------------------------

(define-llvm LLVM-Dispose-Memory-Buffer
  (_fun _LLVM-Memory-Buffer-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Get-Buffer-Start
  (_fun _LLVM-Memory-Buffer-Ref -> _pointer))

(define-llvm LLVM-Get-Buffer-Size
  (_fun _LLVM-Memory-Buffer-Ref -> _size))
