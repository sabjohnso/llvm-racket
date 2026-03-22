#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine
           llvm/private/ffi/linker)

  (test-case "link two modules and verify combined IR"
    (define ctx (LLVM-Context-Create))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Module A: define i32 @add(i32, i32)
    (define mod-a (LLVM-Module-Create-With-Name-In-Context "a" ctx))
    (define add-fn (LLVM-Add-Function mod-a "add"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define add-bb (LLVM-Append-Basic-Block-In-Context ctx add-fn "entry"))
    (define add-bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End add-bld add-bb)
    (LLVM-Build-Ret add-bld
      (LLVM-Build-Add add-bld (LLVM-Get-Param add-fn 0)
                              (LLVM-Get-Param add-fn 1) "r"))

    ;; Module B: define i32 @mul(i32, i32)
    (define mod-b (LLVM-Module-Create-With-Name-In-Context "b" ctx))
    (define mul-fn (LLVM-Add-Function mod-b "mul"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define mul-bb (LLVM-Append-Basic-Block-In-Context ctx mul-fn "entry"))
    (define mul-bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End mul-bld mul-bb)
    (LLVM-Build-Ret mul-bld
      (LLVM-Build-Mul mul-bld (LLVM-Get-Param mul-fn 0)
                              (LLVM-Get-Param mul-fn 1) "r"))

    ;; Link B into A (B is consumed)
    (LLVM-Link-Modules2 mod-a mod-b)

    ;; A should now contain both functions
    (define ir-ptr (LLVM-Print-Module-To-String mod-a))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "@add"))
    (check-true (string-contains? ir "@mul")))

  (test-case "JIT: linked modules — call both functions"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Module A: add
    (define mod-a (LLVM-Module-Create-With-Name-In-Context "a" ctx))
    (define add-fn (LLVM-Add-Function mod-a "add"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define add-bb (LLVM-Append-Basic-Block-In-Context ctx add-fn "entry"))
    (define bld-a (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld-a add-bb)
    (LLVM-Build-Ret bld-a
      (LLVM-Build-Add bld-a (LLVM-Get-Param add-fn 0)
                            (LLVM-Get-Param add-fn 1) "r"))

    ;; Module B: mul
    (define mod-b (LLVM-Module-Create-With-Name-In-Context "b" ctx))
    (define mul-fn (LLVM-Add-Function mod-b "mul"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define mul-bb (LLVM-Append-Basic-Block-In-Context ctx mul-fn "entry"))
    (define bld-b (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld-b mul-bb)
    (LLVM-Build-Ret bld-b
      (LLVM-Build-Mul bld-b (LLVM-Get-Param mul-fn 0)
                            (LLVM-Get-Param mul-fn 1) "r"))

    ;; Link B into A
    (LLVM-Link-Modules2 mod-a mod-b)
    (LLVM-Verify-Module mod-a 'LLVMReturnStatusAction)

    ;; JIT the combined module
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod-a opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

    (define add (cast (LLVM-Get-Function-Address ee "add")
                      _uint64 (_fun _int32 _int32 -> _int32)))
    (define mul (cast (LLVM-Get-Function-Address ee "mul")
                      _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (add 3 4) 7)
    (check-equal? (mul 6 7) 42)))
