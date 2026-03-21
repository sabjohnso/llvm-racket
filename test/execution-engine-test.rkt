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

    ;; Build IR: define i32 @add(i32 %a, i32 %b) { ret i32 add(%a, %b) }
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "jit_test" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "add" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (define tmp (LLVM-Build-Add builder (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1) "tmp"))
    (LLVM-Build-Ret builder tmp)
    (LLVM-Dispose-Builder builder)

    ;; Verify
    (define-values (verify-failed? verify-err) (LLVM-Verify-Module mod 'LLVMReturnStatusAction))
    (check-equal? verify-failed? 0 "module verification should succeed")
    (when (and (not (zero? verify-failed?)) verify-err)
      (LLVM-Dispose-Message verify-err))

    ;; Create MCJIT engine
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define-values (ee-failed? ee ee-err)
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (check-equal? ee-failed? 0
                  (if (and (not (zero? ee-failed?)) ee-err)
                      (let ([msg (cast ee-err _pointer _string)])
                        (LLVM-Dispose-Message ee-err)
                        msg)
                      "MCJIT engine creation failed"))

    ;; Call via LLVM-Get-Function-Address (preferred for MCJIT)
    (define addr (LLVM-Get-Function-Address ee "add"))
    (check-true (> addr 0) "function address should be non-zero")

    ;; Cast address to callable function pointer and invoke
    (define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
    (define result (add-fn 3 4))
    (check-equal? result 7 "add(3, 4) should equal 7")

    ;; Cleanup — engine owns the module, don't dispose module separately
    (LLVM-Dispose-Execution-Engine ee)
    (LLVM-Context-Dispose ctx)))
