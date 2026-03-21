#lang racket/base

(module+ test
  (require rackunit
           llvm/private/ffi/core
           llvm/private/ffi/analysis)

  (test-case "verify valid add module succeeds"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "test" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "add" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (define tmp (LLVM-Build-Add builder (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1) "tmp"))
    (LLVM-Build-Ret builder tmp)

    (define-values (failed? err) (LLVM-Verify-Module mod 'LLVMReturnStatusAction))
    (check-equal? failed? 0 "verification should succeed")
    (when err (LLVM-Dispose-Message err))

    (LLVM-Dispose-Builder builder)
    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx))

  (test-case "verify invalid module fails"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "bad" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32) 1 0))
    ;; Function with a body that has no terminator — invalid IR
    (define fn (LLVM-Add-Function mod "bad" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    ;; Add an instruction but no terminator (missing ret)
    (LLVM-Build-Add builder (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 0) "tmp")
    (LLVM-Dispose-Builder builder)

    (define-values (failed? err) (LLVM-Verify-Module mod 'LLVMReturnStatusAction))
    (check-not-equal? failed? 0 "verification should fail for block without terminator")
    (when err (LLVM-Dispose-Message err))

    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx)))
