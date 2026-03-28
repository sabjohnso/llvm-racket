#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "enums.rkt")

(provide LLVM-Add-Function
         LLVM-Get-Param
         LLVM-Append-Basic-Block-In-Context
         LLVM-Create-Builder-In-Context
         LLVM-Position-Builder-At-End
         LLVM-Dispose-Builder
         ;; Arithmetic
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
         ;; Bitwise
         LLVM-Build-And
         LLVM-Build-Or
         LLVM-Build-Xor
         LLVM-Build-Shl
         LLVM-Build-LShr
         LLVM-Build-AShr
         LLVM-Build-Not
         ;; Comparison
         LLVM-Build-ICmp
         LLVM-Build-FCmp
         ;; Control flow
         LLVM-Build-Br
         LLVM-Build-Cond-Br
         LLVM-Build-Switch
         LLVM-Add-Case
         LLVM-Build-Phi
         LLVM-Add-Incoming
         LLVM-Build-Select
         LLVM-Build-Unreachable
         ;; Cast / conversion
         LLVM-Build-Trunc
         LLVM-Build-ZExt
         LLVM-Build-SExt
         LLVM-Build-FPTo-UI
         LLVM-Build-FPTo-SI
         LLVM-Build-UITo-FP
         LLVM-Build-SITo-FP
         LLVM-Build-Bit-Cast
         LLVM-Build-Int-To-Ptr
         LLVM-Build-Ptr-To-Int
         ;; Function call
         LLVM-Build-Call2
         ;; Memory
         LLVM-Build-Alloca
         LLVM-Build-Load2
         LLVM-Build-Store
         LLVM-Build-GEP2
         ;; Vector
         LLVM-Build-Extract-Element
         LLVM-Build-Insert-Element
         LLVM-Build-Shuffle-Vector
         ;; Terminators
         LLVM-Build-Ret
         LLVM-Build-Ret-Void
         ;; Builder state
         LLVM-Get-Insert-Block)

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

;; ---- Shared FFI types ------------------------------------------------------

(define _build-binop
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref))

(define _build-unop
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref))

(define _build-cast
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Type-Ref _string -> _LLVM-Value-Ref))

;; ---- Integer Arithmetic ----------------------------------------------------

(define-llvm LLVM-Build-Add    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Sub    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-NSWSub _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Mul    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-NSWMul _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-UDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SRem   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-URem   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Neg    _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Floating Point Arithmetic ---------------------------------------------

(define-llvm LLVM-Build-FAdd   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FSub   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FMul   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FDiv   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FNeg   _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Bitwise ---------------------------------------------------------------

(define-llvm LLVM-Build-And    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Or     _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Xor    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Shl    _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-LShr   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-AShr   _build-binop #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Not    _build-unop  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Comparisons -----------------------------------------------------------

(define-llvm LLVM-Build-ICmp
  (_fun _LLVM-Builder-Ref _LLVM-Int-Predicate _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-FCmp
  (_fun _LLVM-Builder-Ref _LLVM-Real-Predicate _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Control Flow ----------------------------------------------------------

(define-llvm LLVM-Build-Br
  (_fun _LLVM-Builder-Ref _LLVM-Basic-Block-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Cond-Br
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Basic-Block-Ref _LLVM-Basic-Block-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Switch
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Basic-Block-Ref _uint -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Add-Case
  (_fun _LLVM-Value-Ref _LLVM-Value-Ref _LLVM-Basic-Block-Ref -> _void))

(define-llvm LLVM-Build-Phi
  (_fun _LLVM-Builder-Ref _LLVM-Type-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Add-Incoming
  (_fun _LLVM-Value-Ref
        (_list i _LLVM-Value-Ref)
        (_list i _LLVM-Basic-Block-Ref)
        _uint
        -> _void))

(define-llvm LLVM-Build-Select
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Unreachable
  (_fun _LLVM-Builder-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Cast / Conversion -----------------------------------------------------

(define-llvm LLVM-Build-Trunc      _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-ZExt       _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SExt       _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FPTo-UI    _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-FPTo-SI    _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-UITo-FP    _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-SITo-FP    _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Bit-Cast   _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Int-To-Ptr _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))
(define-llvm LLVM-Build-Ptr-To-Int _build-cast #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Function Call ---------------------------------------------------------

(define-llvm LLVM-Build-Call2
  (_fun _LLVM-Builder-Ref
        _LLVM-Type-Ref
        _LLVM-Value-Ref
        (_list i _LLVM-Value-Ref)
        _uint
        _string
        -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Memory ----------------------------------------------------------------

(define-llvm LLVM-Build-Alloca
  (_fun _LLVM-Builder-Ref _LLVM-Type-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Load2
  (_fun _LLVM-Builder-Ref _LLVM-Type-Ref _LLVM-Value-Ref _string -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Store
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-GEP2
  (_fun _LLVM-Builder-Ref
        _LLVM-Type-Ref
        _LLVM-Value-Ref
        (_list i _LLVM-Value-Ref)
        _uint
        _string
        -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Vector operations -----------------------------------------------------

(define-llvm LLVM-Build-Extract-Element
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string
        -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Insert-Element
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string
        -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Shuffle-Vector
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref _LLVM-Value-Ref _LLVM-Value-Ref _string
        -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Terminators -----------------------------------------------------------

(define-llvm LLVM-Build-Ret
  (_fun _LLVM-Builder-Ref _LLVM-Value-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

(define-llvm LLVM-Build-Ret-Void
  (_fun _LLVM-Builder-Ref -> _LLVM-Value-Ref)
  #:wrap (lambda (proc) (instruction-wrap proc)))

;; ---- Builder State ---------------------------------------------------------

(define-llvm LLVM-Get-Insert-Block
  (_fun _LLVM-Builder-Ref -> _LLVM-Basic-Block-Ref))
