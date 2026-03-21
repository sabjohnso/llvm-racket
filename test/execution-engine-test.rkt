#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine)

  ;; Helper: build a two-arg i32 function, JIT it, return a callable.
  ;; body-builder receives (builder, param-a, param-b) and must emit
  ;; instructions ending with ret.
  (define (jit-i32-binop name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _int32 _int32 -> _int32)))

  ;; Helper: one-arg i32 function.
  (define (jit-i32-unop name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type i32 (list i32) 1 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _int32 -> _int32)))

  ;; Helper: two-arg double function.
  (define (jit-f64-binop name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type dbl (list dbl dbl) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _double _double -> _double)))

  ;; Helper: one-arg double function.
  (define (jit-f64-unop name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type dbl (list dbl) 1 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _double -> _double)))

  ;; ---- Integer arithmetic ----------------------------------------------------

  (test-case "JIT add(3, 4) = 7"
    (define f (jit-i32-binop "add"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Add bld a b "r")))))
    (check-equal? (f 3 4) 7))

  (test-case "JIT sub(10, 3) = 7"
    (define f (jit-i32-binop "sub"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Sub bld a b "r")))))
    (check-equal? (f 10 3) 7))

  (test-case "JIT mul(6, 7) = 42"
    (define f (jit-i32-binop "mul"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Mul bld a b "r")))))
    (check-equal? (f 6 7) 42))

  (test-case "JIT sdiv(42, 6) = 7"
    (define f (jit-i32-binop "sdiv"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-SDiv bld a b "r")))))
    (check-equal? (f 42 6) 7))

  (test-case "JIT udiv(42, 6) = 7"
    (define f (jit-i32-binop "udiv"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-UDiv bld a b "r")))))
    (check-equal? (f 42 6) 7))

  (test-case "JIT srem(10, 3) = 1"
    (define f (jit-i32-binop "srem"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-SRem bld a b "r")))))
    (check-equal? (f 10 3) 1))

  (test-case "JIT urem(10, 3) = 1"
    (define f (jit-i32-binop "urem"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-URem bld a b "r")))))
    (check-equal? (f 10 3) 1))

  (test-case "JIT neg(5) = -5"
    (define f (jit-i32-unop "neg"
                (lambda (bld a) (LLVM-Build-Ret bld (LLVM-Build-Neg bld a "r")))))
    (check-equal? (f 5) -5))

  ;; ---- Floating point arithmetic ---------------------------------------------

  (test-case "JIT fadd(1.5, 2.5) = 4.0"
    (define f (jit-f64-binop "fadd"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FAdd bld a b "r")))))
    (check-= (f 1.5 2.5) 4.0 0.0))

  (test-case "JIT fsub(10.0, 3.5) = 6.5"
    (define f (jit-f64-binop "fsub"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FSub bld a b "r")))))
    (check-= (f 10.0 3.5) 6.5 0.0))

  (test-case "JIT fmul(3.0, 2.5) = 7.5"
    (define f (jit-f64-binop "fmul"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FMul bld a b "r")))))
    (check-= (f 3.0 2.5) 7.5 0.0))

  (test-case "JIT fdiv(7.5, 2.5) = 3.0"
    (define f (jit-f64-binop "fdiv"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FDiv bld a b "r")))))
    (check-= (f 7.5 2.5) 3.0 0.0))

  (test-case "JIT fneg(3.14) = -3.14"
    (define f (jit-f64-unop "fneg"
                (lambda (bld a) (LLVM-Build-Ret bld (LLVM-Build-FNeg bld a "r")))))
    (check-= (f 3.14) -3.14 0.0))

  ;; ---- Bitwise ---------------------------------------------------------------

  (test-case "JIT and(0xFF, 0x0F) = 0x0F"
    (define f (jit-i32-binop "and"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-And bld a b "r")))))
    (check-equal? (f #xFF #x0F) #x0F))

  (test-case "JIT or(0xF0, 0x0F) = 0xFF"
    (define f (jit-i32-binop "or"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Or bld a b "r")))))
    (check-equal? (f #xF0 #x0F) #xFF))

  (test-case "JIT xor(0xFF, 0x0F) = 0xF0"
    (define f (jit-i32-binop "xor"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Xor bld a b "r")))))
    (check-equal? (f #xFF #x0F) #xF0))

  (test-case "JIT shl(1, 4) = 16"
    (define f (jit-i32-binop "shl"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-Shl bld a b "r")))))
    (check-equal? (f 1 4) 16))

  (test-case "JIT lshr(16, 2) = 4"
    (define f (jit-i32-binop "lshr"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-LShr bld a b "r")))))
    (check-equal? (f 16 2) 4))

  (test-case "JIT ashr(-16, 2) = -4"
    (define f (jit-i32-binop "ashr"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-AShr bld a b "r")))))
    (check-equal? (f -16 2) -4))

  (test-case "JIT not(0) = -1"
    (define f (jit-i32-unop "not"
                (lambda (bld a) (LLVM-Build-Ret bld (LLVM-Build-Not bld a "r")))))
    (check-equal? (f 0) -1))

  ;; ---- Comparisons -----------------------------------------------------------

  ;; ICmp returns i1.  We return it as i1 and use _bool on the Racket side.
  ;; Helper: two-arg i32 predicate returning bool.
  (define (jit-i32-cmp name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type i1 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _int32 _int32 -> _bool)))

  ;; Helper: two-arg double predicate returning bool.
  (define (jit-f64-cmp name body-builder)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod name
                 (LLVM-Function-Type i1 (list dbl dbl) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (body-builder bld (LLVM-Get-Param fn 0) (LLVM-Get-Param fn 1))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee name)
          _uint64 (_fun _double _double -> _bool)))

  (test-case "JIT icmp eq: 5 == 5 is true, 5 == 3 is false"
    (define f (jit-i32-cmp "ieq"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-ICmp bld 'LLVMIntEQ a b "r")))))
    (check-true  (f 5 5))
    (check-false (f 5 3)))

  (test-case "JIT icmp slt: 3 < 5 is true, 5 < 3 is false"
    (define f (jit-i32-cmp "islt"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-ICmp bld 'LLVMIntSLT a b "r")))))
    (check-true  (f 3 5))
    (check-false (f 5 3)))

  (test-case "JIT icmp sgt: 5 > 3 is true, 3 > 5 is false"
    (define f (jit-i32-cmp "isgt"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-ICmp bld 'LLVMIntSGT a b "r")))))
    (check-true  (f 5 3))
    (check-false (f 3 5)))

  (test-case "JIT fcmp oeq: 1.0 == 1.0 is true, 1.0 == 2.0 is false"
    (define f (jit-f64-cmp "foeq"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FCmp bld 'LLVMRealOEQ a b "r")))))
    (check-true  (f 1.0 1.0))
    (check-false (f 1.0 2.0)))

  (test-case "JIT fcmp olt: 1.0 < 2.0 is true, 2.0 < 1.0 is false"
    (define f (jit-f64-cmp "folt"
                (lambda (bld a b) (LLVM-Build-Ret bld (LLVM-Build-FCmp bld 'LLVMRealOLT a b "r")))))
    (check-true  (f 1.0 2.0))
    (check-false (f 2.0 1.0)))

  ;; ---- Control flow -----------------------------------------------------------

  (test-case "JIT select: cond ? a : b"
    ;; select(cond, a, b) — no branching needed
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "select" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i1  (LLVM-Int1-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "select"
                 (LLVM-Function-Type i32 (list i1 i32 i32) 3 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Select bld
                         (LLVM-Get-Param fn 0)
                         (LLVM-Get-Param fn 1)
                         (LLVM-Get-Param fn 2)
                         "sel"))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (define f (cast (LLVM-Get-Function-Address ee "select")
                    _uint64 (_fun _bool _int32 _int32 -> _int32)))
    (check-equal? (f #t 10 20) 10)
    (check-equal? (f #f 10 20) 20))

  (test-case "JIT if-then-else via condbr + phi"
    ;; max(a, b) using condbr + phi
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "max" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "max"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define entry-bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define then-bb  (LLVM-Append-Basic-Block-In-Context ctx fn "then"))
    (define else-bb  (LLVM-Append-Basic-Block-In-Context ctx fn "else"))
    (define merge-bb (LLVM-Append-Basic-Block-In-Context ctx fn "merge"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (define a (LLVM-Get-Param fn 0))
    (define b (LLVM-Get-Param fn 1))

    ;; entry: if a > b then goto then else goto else
    (LLVM-Position-Builder-At-End bld entry-bb)
    (define cond (LLVM-Build-ICmp bld 'LLVMIntSGT a b "cond"))
    (LLVM-Build-Cond-Br bld cond then-bb else-bb)

    ;; then: br merge
    (LLVM-Position-Builder-At-End bld then-bb)
    (LLVM-Build-Br bld merge-bb)

    ;; else: br merge
    (LLVM-Position-Builder-At-End bld else-bb)
    (LLVM-Build-Br bld merge-bb)

    ;; merge: phi [a, then], [b, else]; ret
    (LLVM-Position-Builder-At-End bld merge-bb)
    (define phi (LLVM-Build-Phi bld i32 "result"))
    (LLVM-Add-Incoming phi (list a b) (list then-bb else-bb) 2)
    (LLVM-Build-Ret bld phi)

    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (define max-fn (cast (LLVM-Get-Function-Address ee "max")
                         _uint64 (_fun _int32 _int32 -> _int32)))
    (check-equal? (max-fn 10 3) 10)
    (check-equal? (max-fn 3 10) 10)
    (check-equal? (max-fn 5 5) 5)))
