#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/unsafe)

  (test-case "end-to-end: build IR, verify, JIT, call add(3,4) = 7"
    ;; Initialize
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)

    ;; Build IR
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "e2e" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "add"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                          (LLVM-Get-Param fn 1) "tmp"))

    ;; Verify and JIT
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

    ;; Call native code
    (define add-fn
      (cast (LLVM-Get-Function-Address ee "add")
            _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (add-fn 3 4) 7)))
