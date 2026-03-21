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
    (LLVM-Context-Dispose ctx))

  (test-case "integer types: i1, i8, i16, i32, i64, arbitrary width"
    (define ctx (LLVM-Context-Create))

    (check-not-false (LLVM-Int1-Type-In-Context ctx))
    (check-not-false (LLVM-Int8-Type-In-Context ctx))
    (check-not-false (LLVM-Int16-Type-In-Context ctx))
    (check-not-false (LLVM-Int32-Type-In-Context ctx))
    (check-not-false (LLVM-Int64-Type-In-Context ctx))
    (check-not-false (LLVM-Int-Type-In-Context ctx 128))

    (LLVM-Context-Dispose ctx))

  (test-case "float and double types"
    (define ctx (LLVM-Context-Create))

    (check-not-false (LLVM-Float-Type-In-Context ctx))
    (check-not-false (LLVM-Double-Type-In-Context ctx))

    (LLVM-Context-Dispose ctx))

  (test-case "void and pointer types"
    (define ctx (LLVM-Context-Create))

    (check-not-false (LLVM-Void-Type-In-Context ctx))
    (check-not-false (LLVM-Pointer-Type-In-Context ctx 0))

    (LLVM-Context-Dispose ctx))

  (test-case "struct types"
    (define ctx (LLVM-Context-Create))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i64 (LLVM-Int64-Type-In-Context ctx))

    ;; Anonymous struct
    (define s (LLVM-Struct-Type-In-Context ctx (list i32 i64) 2 0))
    (check-not-false s)

    ;; Named struct
    (define named (LLVM-Struct-Create-Named ctx "pair"))
    (check-not-false named)
    (LLVM-Struct-Set-Body named (list i32 i64) 2 0)

    (LLVM-Context-Dispose ctx))

  (test-case "array and vector types"
    (define ctx (LLVM-Context-Create))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    (check-not-false (LLVM-Array-Type i32 10))
    (check-not-false (LLVM-Vector-Type i32 4))

    (LLVM-Context-Dispose ctx))

  (test-case "build function with void return"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "void-test" ctx))
    (define void-ty (LLVM-Void-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type void-ty '() 0 0))
    (define fn (LLVM-Add-Function mod "nop" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (LLVM-Build-Ret-Void builder)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "void"))

    (LLVM-Dispose-Builder builder)
    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx)))
