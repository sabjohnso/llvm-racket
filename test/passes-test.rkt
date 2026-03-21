#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/target-machine
           llvm/private/ffi/execution-engine
           llvm/private/ffi/passes)

  ;; Helper: build a simple add(i32,i32)->i32 module
  (define (build-add-module)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "opt" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "add"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                          (LLVM-Get-Param fn 1) "r"))
    (values ctx mod fn))

  ;; Helper: build a function with redundant alloca/store/load
  ;; that mem2reg should optimize away
  (define (build-redundant-load-module)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "opt" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "identity"
                 (LLVM-Function-Type i32 (list i32) 1 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    ;; Redundant: alloca, store, load — should be eliminated by mem2reg
    (define slot (LLVM-Build-Alloca bld i32 "slot"))
    (LLVM-Build-Store bld (LLVM-Get-Param fn 0) slot)
    (define loaded (LLVM-Build-Load2 bld i32 slot "loaded"))
    (LLVM-Build-Ret bld loaded)
    (values ctx mod fn))

  ;; ---- New pass manager ------------------------------------------------------

  (test-case "new pass manager: run optimization pipeline"
    (Initialize-Native-Target!)
    (define-values (ctx mod fn) (build-redundant-load-module))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    ;; Get target machine for the pass manager
    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))

    ;; Run mem2reg to eliminate the redundant alloca
    (define opts (LLVM-Create-Pass-Builder-Options))
    (check-not-false opts)
    (LLVM-Run-Passes mod "mem2reg" tm opts)

    ;; After optimization, alloca should be gone
    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-false (string-contains? ir "alloca")
                 "mem2reg should eliminate the redundant alloca"))

  (test-case "new pass manager: default<O2> pipeline"
    (Initialize-Native-Target!)
    (define-values (ctx mod fn) (build-add-module))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))

    (define opts (LLVM-Create-Pass-Builder-Options))
    ;; Should not raise — valid pipeline
    (check-not-exn
     (lambda () (LLVM-Run-Passes mod "default<O2>" tm opts))))

  (test-case "new pass manager: invalid pipeline raises"
    (Initialize-Native-Target!)
    (define-values (ctx mod fn) (build-add-module))

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))

    (define opts (LLVM-Create-Pass-Builder-Options))
    (check-exn exn:fail?
               (lambda () (LLVM-Run-Passes mod "not-a-real-pass" tm opts))))

  ;; ---- Legacy pass manager ---------------------------------------------------

  (test-case "legacy pass manager: module passes"
    (define-values (ctx mod fn) (build-add-module))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    (define pm (LLVM-Create-Pass-Manager))
    (check-not-false pm)
    (LLVM-Add-Instruction-Combining-Pass pm)
    (LLVM-Add-Reassociate-Pass pm)
    (LLVM-Add-GVN-Pass pm)
    (LLVM-Add-CFG-Simplification-Pass pm)
    (LLVM-Add-Scalar-Repl-Aggregates-Pass-SSA pm)
    (LLVM-Run-Pass-Manager pm mod))

  (test-case "legacy pass manager: function passes with mem2reg"
    (define-values (ctx mod fn) (build-redundant-load-module))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    (define fpm (LLVM-Create-Function-Pass-Manager-For-Module mod))
    (check-not-false fpm)
    (LLVM-Add-Promote-Memory-To-Register-Pass fpm)
    (LLVM-Add-Instruction-Combining-Pass fpm)
    (LLVM-Initialize-Function-Pass-Manager fpm)
    (LLVM-Run-Function-Pass-Manager fpm fn)
    (LLVM-Finalize-Function-Pass-Manager fpm)

    ;; After mem2reg, alloca should be gone
    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-false (string-contains? ir "alloca")
                 "mem2reg should eliminate the redundant alloca"))

  ;; ---- JIT: verify optimization doesn't break execution ----------------------

  (test-case "JIT: optimized function still computes correctly"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define-values (ctx mod fn) (build-redundant-load-module))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    ;; Optimize with legacy FPM
    (define fpm (LLVM-Create-Function-Pass-Manager-For-Module mod))
    (LLVM-Add-Promote-Memory-To-Register-Pass fpm)
    (LLVM-Add-Instruction-Combining-Pass fpm)
    (LLVM-Initialize-Function-Pass-Manager fpm)
    (LLVM-Run-Function-Pass-Manager fpm fn)
    (LLVM-Finalize-Function-Pass-Manager fpm)

    ;; JIT and call
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (define f (cast (LLVM-Get-Function-Address ee "identity")
                    _uint64 (_fun _int32 -> _int32)))
    (check-equal? (f 42) 42)
    (check-equal? (f -7) -7)))
