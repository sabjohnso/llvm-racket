#lang racket/base

(module+ test
  (require rackunit
           racket/string
           racket/file
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine
           llvm/private/ffi/bitcode)

  ;; Helper: build a simple add(i32,i32)->i32 module
  (define (build-add-module)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "bc" ctx))
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
    (values ctx mod))

  ;; ---- Bitcode write/read round-trip -----------------------------------------

  (test-case "write bitcode to file and read back"
    (define-values (ctx mod) (build-add-module))
    (define tmp (make-temporary-file "llvm-bc-~a.bc"))

    ;; Write
    (LLVM-Write-Bitcode-To-File mod (path->string tmp))

    ;; Read into new context
    (define ctx2 (LLVM-Context-Create))
    (define mod2 (LLVM-Parse-Bitcode-File ctx2 (path->string tmp)))
    (check-not-false mod2)

    ;; Verify the loaded module has the function
    (define ir-ptr (LLVM-Print-Module-To-String mod2))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "add"))

    (delete-file tmp))

  (test-case "write bitcode to memory buffer and read back"
    (define-values (ctx mod) (build-add-module))

    ;; Write to buffer
    (define buf (LLVM-Write-Bitcode-To-Memory-Buffer mod))
    (check-not-false buf)
    (check-true (> (LLVM-Get-Buffer-Size buf) 0))

    ;; Read from buffer
    (define ctx2 (LLVM-Context-Create))
    (define mod2 (LLVM-Parse-Bitcode-In-Context2 ctx2 buf))
    (check-not-false mod2)

    (define ir-ptr (LLVM-Print-Module-To-String mod2))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "add")))

  ;; ---- IR text round-trip ----------------------------------------------------

  (test-case "parse IR text"
    (define ctx (LLVM-Context-Create))
    (define ir-text
      (string-append
       "define i32 @double(i32 %x) {\n"
       "entry:\n"
       "  %r = add i32 %x, %x\n"
       "  ret i32 %r\n"
       "}\n"))
    (define buf (LLVM-Create-Memory-Buffer-With-Memory-Range
                 ir-text (string-length ir-text) "ir" 0))
    (define mod (LLVM-Parse-IR-In-Context ctx buf))
    (check-not-false mod)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "double")))

  ;; ---- Module utilities ------------------------------------------------------

  (test-case "clone module"
    (define-values (ctx mod) (build-add-module))
    (define mod2 (LLVM-Clone-Module mod))
    (check-not-false mod2)

    (define ir-ptr (LLVM-Print-Module-To-String mod2))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "add")))

  (test-case "set and get target triple"
    (define-values (ctx mod) (build-add-module))
    (LLVM-Set-Target mod "x86_64-unknown-linux-gnu")
    (check-equal? (LLVM-Get-Target mod) "x86_64-unknown-linux-gnu"))

  (test-case "set and get data layout"
    (define-values (ctx mod) (build-add-module))
    (define layout "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128")
    (LLVM-Set-Data-Layout mod layout)
    (check-equal? (LLVM-Get-Data-Layout mod) layout))

  ;; ---- JIT: bitcode round-trip preserves execution ---------------------------

  (test-case "JIT: bitcode round-trip preserves add(3,4) = 7"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define-values (ctx mod) (build-add-module))

    ;; Round-trip through bitcode buffer
    (define buf (LLVM-Write-Bitcode-To-Memory-Buffer mod))
    (define ctx2 (LLVM-Context-Create))
    (define mod2 (LLVM-Parse-Bitcode-In-Context2 ctx2 buf))

    ;; JIT the loaded module
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod2 opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (define f (cast (LLVM-Get-Function-Address ee "add")
                    _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (f 3 4) 7))

  ;; ---- Error paths -----------------------------------------------------------

  (test-case "parse malformed IR text raises"
    (define ctx (LLVM-Context-Create))
    (define buf (LLVM-Create-Memory-Buffer-With-Memory-Range
                 "this is not valid IR" 20 "bad" 0))
    (check-exn exn:fail?
               (lambda () (LLVM-Parse-IR-In-Context ctx buf))))

  (test-case "read non-existent file raises"
    (check-exn exn:fail?
               (lambda ()
                 (LLVM-Create-Memory-Buffer-With-Contents-Of-File
                  "/tmp/llvm-racket-does-not-exist-abc123.bc")))))
