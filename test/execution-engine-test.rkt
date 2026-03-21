#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine)

  (test-case "MCJIT: build add(i32,i32), JIT compile, call add(3,4) = 7"
    ;; Initialize
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)

    ;; Build IR
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "jit_test" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "add" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (LLVM-Build-Ret builder
                    (LLVM-Build-Add builder
                                   (LLVM-Get-Param fn 0)
                                   (LLVM-Get-Param fn 1) "tmp"))

    ;; Verify — raises on failure
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    ;; Create MCJIT engine — raises on failure, returns engine
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

    ;; Call via LLVM-Get-Function-Address
    (define addr (LLVM-Get-Function-Address ee "add"))
    (check-true (> addr 0) "function address should be non-zero")

    (define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (add-fn 3 4) 7 "add(3, 4) should equal 7")))
