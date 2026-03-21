#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "enums.rkt"
         "core.rkt")

(provide LLVM-Link-In-MCJIT
         LLVM-Create-MCJIT-Compiler-For-Module
         LLVM-Initialize-MCJIT-Compiler-Options
         LLVM-Get-Function-Address
         LLVM-Dispose-Execution-Engine
         LLVM-Create-Generic-Value-Of-Int
         LLVM-Run-Function
         LLVM-Generic-Value-To-Int
         LLVM-Dispose-Generic-Value
         _LLVM-MCJIT-Compiler-Options
         make-LLVM-MCJIT-Compiler-Options)

;; MCJITCompilerOptions struct
(define-cstruct _LLVM-MCJIT-Compiler-Options
  ([OptLevel _uint]
   [CodeModel _LLVM-Code-Model]
   [NoFramePointerElim _LLVM-Bool]
   [EnableFastISel _LLVM-Bool]
   [MCJMM _pointer]))  ; _LLVM-MCJIT-Memory-Manager-Ref/null

;; Link in MCJIT — must be called before creating an execution engine.
(define-llvm LLVM-Link-In-MCJIT
  (_fun -> _void))

;; Initialize options struct to safe defaults.
(define-llvm LLVM-Initialize-MCJIT-Compiler-Options
  (_fun _LLVM-MCJIT-Compiler-Options-pointer _size -> _void))

;; Execution engine
(define-llvm LLVM-Dispose-Execution-Engine
  (_fun _LLVM-Execution-Engine-Ref -> _void)
  #:wrap (deallocator))

;; Register out-param engine with the allocator mechanism.
(define register-engine!
  (make-register-allocation LLVM-Dispose-Execution-Engine))

;; Create MCJIT execution engine.  Module ownership transfers to engine.
;; Raises exn:fail on error.  Returns the execution engine on success.
(define-llvm LLVM-Create-MCJIT-Compiler-For-Module
  (_fun (ee : (_ptr o _LLVM-Execution-Engine-Ref))
        _LLVM-Module-Ref
        _LLVM-MCJIT-Compiler-Options-pointer
        _size
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result ee err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (mod opts size)
               (define-values (result ee err) (proc mod opts size))
               (check-llvm-error 'LLVM-Create-MCJIT-Compiler-For-Module result err)
               (register-engine! ee)
               (cancel-module-ownership! mod)
               (prevent-gc! ee mod)
               ee))))

;; Get address of a JIT'd function. Returns 0 on failure.
(define-llvm LLVM-Get-Function-Address
  (_fun _LLVM-Execution-Engine-Ref _string -> _uint64))

;; GenericValue API for calling JIT'd functions via LLVMRunFunction.
(define-llvm LLVM-Dispose-Generic-Value
  (_fun _LLVM-Generic-Value-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Generic-Value-Of-Int
  (_fun _LLVM-Type-Ref _ullong _LLVM-Bool -> _LLVM-Generic-Value-Ref)
  #:wrap (allocator LLVM-Dispose-Generic-Value))

(define-llvm LLVM-Run-Function
  (_fun _LLVM-Execution-Engine-Ref
        _LLVM-Value-Ref
        _uint
        (_list i _LLVM-Generic-Value-Ref)
        -> _LLVM-Generic-Value-Ref)
  #:wrap (allocator LLVM-Dispose-Generic-Value))

(define-llvm LLVM-Generic-Value-To-Int
  (_fun _LLVM-Generic-Value-Ref _LLVM-Bool -> _ullong))
