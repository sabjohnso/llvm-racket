#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core)

  (test-case "build add(i32, i32) -> i32 function and print IR"
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

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "define"))
    (check-true (string-contains? ir "add"))

    (LLVM-Dispose-Builder builder)
    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx)))
