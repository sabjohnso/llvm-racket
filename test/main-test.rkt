#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/unsafe)

  (test-case "end-to-end: build IR, verify, JIT, call add(3,4) = 7"
    ;; Initialize targets and MCJIT
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)

    ;; Build module with add function
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "e2e" ctx))
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

    ;; Verify
    (define-values (vfail? verr) (LLVM-Verify-Module mod 'LLVMReturnStatusAction))
    (check-equal? vfail? 0)
    (when verr (LLVM-Dispose-Message verr))

    ;; Print IR and sanity-check
    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "define"))

    ;; JIT compile
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define-values (efail? ee eerr)
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (when (and (not (zero? efail?)) eerr)
      (LLVM-Dispose-Message eerr))
    (check-equal? efail? 0)

    ;; Call native code
    (define addr (LLVM-Get-Function-Address ee "add"))
    (check-true (> addr 0))
    (define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (add-fn 3 4) 7)

    ;; Cleanup
    (LLVM-Dispose-Execution-Engine ee)
    (LLVM-Context-Dispose ctx)))
