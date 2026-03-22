#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/iteration)

  ;; Helper: build a module with two functions and a global
  (define (build-test-module)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "iter" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Global
    (define g (LLVM-Add-Global mod i32 "my_global"))
    (LLVM-Set-Initializer g (LLVM-Const-Int i32 0 0))

    ;; Function 1: add
    (define add-fn (LLVM-Add-Function mod "add"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define add-bb (LLVM-Append-Basic-Block-In-Context ctx add-fn "entry"))
    (define bld1 (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld1 add-bb)
    (LLVM-Build-Ret bld1
      (LLVM-Build-Add bld1 (LLVM-Get-Param add-fn 0)
                           (LLVM-Get-Param add-fn 1) "r"))

    ;; Function 2: mul
    (define mul-fn (LLVM-Add-Function mod "mul"
                     (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define mul-bb (LLVM-Append-Basic-Block-In-Context ctx mul-fn "entry"))
    (define bld2 (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld2 mul-bb)
    (LLVM-Build-Ret bld2
      (LLVM-Build-Mul bld2 (LLVM-Get-Param mul-fn 0)
                           (LLVM-Get-Param mul-fn 1) "r"))

    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (values ctx mod))

  (test-case "iterate functions in module"
    (define-values (ctx mod) (build-test-module))
    (define fns (LLVM-Module-Functions mod))
    (check-equal? (length fns) 2)
    (define names (map LLVM-Get-Value-Name fns))
    (check-not-false (member "add" names))
    (check-not-false (member "mul" names)))

  (test-case "iterate globals in module"
    (define-values (ctx mod) (build-test-module))
    (define globals (LLVM-Module-Globals mod))
    (check-equal? (length globals) 1)
    (check-equal? (LLVM-Get-Value-Name (car globals)) "my_global"))

  (test-case "iterate basic blocks in function"
    (define-values (ctx mod) (build-test-module))
    (define fns (LLVM-Module-Functions mod))
    (define add-fn (car fns))
    (define bbs (LLVM-Function-Basic-Blocks add-fn))
    (check-equal? (length bbs) 1))

  (test-case "iterate instructions in basic block"
    (define-values (ctx mod) (build-test-module))
    (define fns (LLVM-Module-Functions mod))
    (define add-fn (car fns))
    (define bbs (LLVM-Function-Basic-Blocks add-fn))
    (define instrs (LLVM-Basic-Block-Instructions (car bbs)))
    ;; Should have at least 2: add + ret
    (check-true (>= (length instrs) 2))))
