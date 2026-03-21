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
    (LLVM-Context-Dispose ctx))

  (test-case "integer arithmetic instructions"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "arith" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "arith" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (define a (LLVM-Get-Param fn 0))
    (define b (LLVM-Get-Param fn 1))

    ;; Exercise each integer arithmetic instruction
    (define v1 (LLVM-Build-Sub builder a b "sub"))
    (define v2 (LLVM-Build-NSWSub builder a b "nswsub"))
    (define v3 (LLVM-Build-Mul builder a b "mul"))
    (define v4 (LLVM-Build-NSWMul builder a b "nswmul"))
    (define v5 (LLVM-Build-SDiv builder a b "sdiv"))
    (define v6 (LLVM-Build-UDiv builder a b "udiv"))
    (define v7 (LLVM-Build-SRem builder a b "srem"))
    (define v8 (LLVM-Build-URem builder a b "urem"))
    (define v9 (LLVM-Build-Neg builder a "neg"))
    (LLVM-Build-Ret builder v1)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "sub"))
    (check-true (string-contains? ir "mul"))
    (check-true (string-contains? ir "sdiv"))
    (check-true (string-contains? ir "udiv"))
    (check-true (string-contains? ir "srem"))
    (check-true (string-contains? ir "urem")))

  (test-case "floating point arithmetic instructions"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "fparith" ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type dbl (list dbl dbl) 2 0))
    (define fn (LLVM-Add-Function mod "fparith" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (define a (LLVM-Get-Param fn 0))
    (define b (LLVM-Get-Param fn 1))

    (define v1 (LLVM-Build-FAdd builder a b "fadd"))
    (define v2 (LLVM-Build-FSub builder a b "fsub"))
    (define v3 (LLVM-Build-FMul builder a b "fmul"))
    (define v4 (LLVM-Build-FDiv builder a b "fdiv"))
    (define v5 (LLVM-Build-FNeg builder a "fneg"))
    (LLVM-Build-Ret builder v1)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "fadd"))
    (check-true (string-contains? ir "fsub"))
    (check-true (string-contains? ir "fmul"))
    (check-true (string-contains? ir "fdiv"))
    (check-true (string-contains? ir "fneg")))

  (test-case "bitwise instructions"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "bitwise" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "bitwise" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (define a (LLVM-Get-Param fn 0))
    (define b (LLVM-Get-Param fn 1))

    (define v1 (LLVM-Build-And  builder a b "and"))
    (define v2 (LLVM-Build-Or   builder a b "or"))
    (define v3 (LLVM-Build-Xor  builder a b "xor"))
    (define v4 (LLVM-Build-Shl  builder a b "shl"))
    (define v5 (LLVM-Build-LShr builder a b "lshr"))
    (define v6 (LLVM-Build-AShr builder a b "ashr"))
    (define v7 (LLVM-Build-Not  builder a "not"))
    (LLVM-Build-Ret builder v1)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "and"))
    (check-true (string-contains? ir "or"))
    (check-true (string-contains? ir "xor"))
    (check-true (string-contains? ir "shl"))
    (check-true (string-contains? ir "lshr"))
    (check-true (string-contains? ir "ashr")))

  (test-case "comparison instructions"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "cmp" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))

    ;; Integer comparison
    (define ifn-type (LLVM-Function-Type i1 (list i32 i32) 2 0))
    (define ifn (LLVM-Add-Function mod "icmp_test" ifn-type))
    (define ibb (LLVM-Append-Basic-Block-In-Context ctx ifn "entry"))
    (define ibld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End ibld ibb)
    (define ia (LLVM-Get-Param ifn 0))
    (define ib (LLVM-Get-Param ifn 1))
    (LLVM-Build-Ret ibld (LLVM-Build-ICmp ibld 'LLVMIntEQ ia ib "eq"))

    ;; Float comparison
    (define ffn-type (LLVM-Function-Type i1 (list dbl dbl) 2 0))
    (define ffn (LLVM-Add-Function mod "fcmp_test" ffn-type))
    (define fbb (LLVM-Append-Basic-Block-In-Context ctx ffn "entry"))
    (define fbld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End fbld fbb)
    (define fa (LLVM-Get-Param ffn 0))
    (define fb (LLVM-Get-Param ffn 1))
    (LLVM-Build-Ret fbld (LLVM-Build-FCmp fbld 'LLVMRealOEQ fa fb "oeq"))

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "icmp eq"))
    (check-true (string-contains? ir "fcmp oeq"))))
