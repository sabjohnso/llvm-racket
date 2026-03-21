#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine)

  ;; Force GC collection and run finalizers.
  (define (force-gc!)
    (collect-garbage)
    (collect-garbage)
    (collect-garbage))

  (test-case "context survives while module is reachable"
    ;; Drop the context reference; the module's prevent-gc anchor
    ;; should keep the context alive.
    (define mod
      (let ()
        (define ctx (LLVM-Context-Create))
        (define m (LLVM-Module-Create-With-Name-In-Context "gc-test" ctx))
        m))
    (force-gc!)
    ;; If the context were finalized, printing IR would crash.
    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string? ir))
    (LLVM-Dispose-Module mod))

  (test-case "module survives while function ref is reachable"
    ;; Drop the module reference; the function's prevent-gc anchor
    ;; should keep the module (and context) alive.
    (define fn
      (let ()
        (define ctx (LLVM-Context-Create))
        (define mod (LLVM-Module-Create-With-Name-In-Context "gc-test" ctx))
        (define i32 (LLVM-Int32-Type-In-Context ctx))
        (define fn-type (LLVM-Function-Type i32 (list i32) 1 0))
        (LLVM-Add-Function mod "f" fn-type)))
    (force-gc!)
    ;; If the module were finalized, getting a param would crash.
    (define param (LLVM-Get-Param fn 0))
    (check-not-false param))

  (test-case "context survives while type ref is reachable"
    (define ty
      (let ()
        (define ctx (LLVM-Context-Create))
        (LLVM-Int32-Type-In-Context ctx)))
    (force-gc!)
    ;; If the context were finalized, using the type would crash.
    ;; Build a function type from it to prove it's still valid.
    (define fn-ty (LLVM-Function-Type ty '() 0 0))
    (check-not-false fn-ty))

  (test-case "engine disposal doesn't double-free transferred module"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)

    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "xfer-test" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "add" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (LLVM-Build-Ret builder
                    (LLVM-Build-Add builder
                                   (LLVM-Get-Param fn 0)
                                   (LLVM-Get-Param fn 1)
                                   "tmp"))
    (LLVM-Dispose-Builder builder)

    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

    ;; Module ownership transferred.  Force GC — the module's finalizer
    ;; should have been canceled, so GC should NOT call LLVM-Dispose-Module.
    ;; Then disposing the engine frees the module via C.  If the finalizer
    ;; weren't canceled, this would double-free and crash.
    (force-gc!)
    (check-not-exn
     (lambda () (LLVM-Dispose-Execution-Engine ee))
     "engine disposal should not double-free the transferred module")))
