#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/orc)

  (test-case "ORC JIT: build add, JIT, call add(3,4) = 7"
    (Initialize-Native-Target!)

    ;; Build module in a thread-safe context
    (define ts-ctx (LLVM-Orc-Create-New-Thread-Safe-Context))
    (check-not-false ts-ctx)
    (define ctx (LLVM-Orc-Thread-Safe-Context-Get-Context ts-ctx))
    (define mod (LLVM-Module-Create-With-Name-In-Context "orc" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "add"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                          (LLVM-Get-Param fn 1) "r"))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    ;; Wrap in thread-safe module (takes ownership of mod)
    (define ts-mod (LLVM-Orc-Create-New-Thread-Safe-Module mod ts-ctx))
    (check-not-false ts-mod)

    ;; Create LLJIT
    (define jit (LLVM-Orc-Create-LLJIT #f))
    (check-not-false jit)

    ;; Add module to main dylib
    (define dylib (LLVM-Orc-LLJIT-Get-Main-JIT-Dylib jit))
    (check-not-false dylib)
    (LLVM-Orc-LLJIT-Add-LLVM-IR-Module jit dylib ts-mod)

    ;; Look up and call
    (define addr (LLVM-Orc-LLJIT-Lookup jit "add"))
    (check-true (> addr 0))
    (define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (add-fn 3 4) 7)
    (check-equal? (add-fn 100 -50) 50))

  (test-case "ORC JIT: lookup nonexistent symbol raises"
    (Initialize-Native-Target!)
    (define jit (LLVM-Orc-Create-LLJIT #f))
    (check-exn exn:fail?
               (lambda () (LLVM-Orc-LLJIT-Lookup jit "no_such_symbol"))))

  (test-case "ORC JIT: get triple string"
    (Initialize-Native-Target!)
    (define jit (LLVM-Orc-Create-LLJIT #f))
    (define triple (LLVM-Orc-LLJIT-Get-Triple-String jit))
    (check-true (string? triple))
    (check-true (> (string-length triple) 0)))

  (test-case "ORC JIT: get execution session"
    (Initialize-Native-Target!)
    (define jit (LLVM-Orc-Create-LLJIT #f))
    (define es (LLVM-Orc-LLJIT-Get-Execution-Session jit))
    (check-not-false es)))
