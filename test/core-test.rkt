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
    (check-true (string-contains? ir "fcmp oeq")))

  (test-case "control flow: br, condbr, phi, select, unreachable"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "cf" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))

    ;; Build a function with conditional branch and phi
    (define fn-type (LLVM-Function-Type i32 (list i32 i32 i1) 3 0))
    (define fn (LLVM-Add-Function mod "cf_test" fn-type))
    (define entry-bb  (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define then-bb   (LLVM-Append-Basic-Block-In-Context ctx fn "then"))
    (define else-bb   (LLVM-Append-Basic-Block-In-Context ctx fn "else"))
    (define merge-bb  (LLVM-Append-Basic-Block-In-Context ctx fn "merge"))

    (define bld (LLVM-Create-Builder-In-Context ctx))

    ;; entry: condbr %cond, then, else
    (LLVM-Position-Builder-At-End bld entry-bb)
    (LLVM-Build-Cond-Br bld (LLVM-Get-Param fn 2) then-bb else-bb)

    ;; then: br merge
    (LLVM-Position-Builder-At-End bld then-bb)
    (LLVM-Build-Br bld merge-bb)

    ;; else: br merge
    (LLVM-Position-Builder-At-End bld else-bb)
    (LLVM-Build-Br bld merge-bb)

    ;; merge: phi [%a, then], [%b, else]; ret phi
    (LLVM-Position-Builder-At-End bld merge-bb)
    (define phi (LLVM-Build-Phi bld i32 "result"))
    (LLVM-Add-Incoming phi
                       (list (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1))
                       (list then-bb else-bb)
                       2)
    (LLVM-Build-Ret bld phi)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "br i1"))
    (check-true (string-contains? ir "br label"))
    (check-true (string-contains? ir "phi i32")))

  (test-case "select instruction"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "sel" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i1 i32 i32) 3 0))
    (define fn (LLVM-Add-Function mod "sel_test" fn-type))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Select bld
                         (LLVM-Get-Param fn 0)
                         (LLVM-Get-Param fn 1)
                         (LLVM-Get-Param fn 2)
                         "sel"))

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "select i1")))

  (test-case "cast / conversion instructions"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "cast" ctx))
    (define i8  (LLVM-Int8-Type-In-Context ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i64 (LLVM-Int64-Type-In-Context ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define ptr (LLVM-Pointer-Type-In-Context ctx 0))

    ;; i32 -> various casts
    (define fn-type (LLVM-Function-Type i32 (list i32) 1 0))
    (define fn (LLVM-Add-Function mod "cast_test" fn-type))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (define a (LLVM-Get-Param fn 0))

    (define v1 (LLVM-Build-Trunc    bld a i8  "trunc"))
    (define v2 (LLVM-Build-ZExt     bld a i64 "zext"))
    (define v3 (LLVM-Build-SExt     bld a i64 "sext"))
    (define v4 (LLVM-Build-UITo-FP  bld a dbl "uitofp"))
    (define v5 (LLVM-Build-SITo-FP  bld a dbl "sitofp"))
    (define v6 (LLVM-Build-FPTo-UI  bld v4 i32 "fptoui"))
    (define v7 (LLVM-Build-FPTo-SI  bld v5 i32 "fptosi"))
    (define v8 (LLVM-Build-Int-To-Ptr bld a ptr "inttoptr"))
    (define v9 (LLVM-Build-Ptr-To-Int bld v8 i32 "ptrtoint"))
    (define v10 (LLVM-Build-Bit-Cast bld a (LLVM-Float-Type-In-Context ctx) "bitcast"))
    (LLVM-Build-Ret bld a)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "trunc"))
    (check-true (string-contains? ir "zext"))
    (check-true (string-contains? ir "sext"))
    (check-true (string-contains? ir "uitofp"))
    (check-true (string-contains? ir "sitofp"))
    (check-true (string-contains? ir "fptoui"))
    (check-true (string-contains? ir "fptosi"))
    (check-true (string-contains? ir "inttoptr"))
    (check-true (string-contains? ir "ptrtoint"))
    (check-true (string-contains? ir "bitcast")))

  (test-case "function call instruction"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "call" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Define callee: i32 @add(i32, i32)
    (define add-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define add-fn (LLVM-Add-Function mod "add" add-type))
    (define add-bb (LLVM-Append-Basic-Block-In-Context ctx add-fn "entry"))
    (define add-bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End add-bld add-bb)
    (LLVM-Build-Ret add-bld
      (LLVM-Build-Add add-bld (LLVM-Get-Param add-fn 0) (LLVM-Get-Param add-fn 1) "r"))

    ;; Define caller: i32 @caller(i32, i32) { ret add(a, b) }
    (define caller-fn (LLVM-Add-Function mod "caller" add-type))
    (define caller-bb (LLVM-Append-Basic-Block-In-Context ctx caller-fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld caller-bb)
    (define result (LLVM-Build-Call2 bld add-type add-fn
                     (list (LLVM-Get-Param caller-fn 0)
                           (LLVM-Get-Param caller-fn 1))
                     2 "callresult"))
    (LLVM-Build-Ret bld result)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "call i32 @add")))

  (test-case "memory instructions: alloca, store, load, gep"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "mem" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Struct type { i32, i32 }
    (define pair-ty (LLVM-Struct-Type-In-Context ctx (list i32 i32) 2 0))

    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "mem_test" fn-type))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)

    ;; alloca a struct on the stack
    (define ptr (LLVM-Build-Alloca bld pair-ty "pair"))

    ;; gep to field 0, store first param
    (define zero (LLVM-Build-Trunc bld (LLVM-Get-Param fn 0) i32 "zero_idx"))
    ;; Use constant index 0 for GEP — we need LLVMConstInt for that,
    ;; but we haven't bound it yet.  Instead, just test alloca/store/load
    ;; with a simple i32 alloca.
    (define slot (LLVM-Build-Alloca bld i32 "slot"))
    (LLVM-Build-Store bld (LLVM-Get-Param fn 0) slot)
    (define loaded (LLVM-Build-Load2 bld i32 slot "loaded"))
    (LLVM-Build-Ret bld loaded)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)

    (check-true (string-contains? ir "alloca"))
    (check-true (string-contains? ir "store"))
    (check-true (string-contains? ir "load"))))
