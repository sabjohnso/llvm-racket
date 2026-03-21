#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/execution-engine)

  (test-case "integer and float constants in IR"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "const" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define dbl (LLVM-Double-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 '() 0 0))
    (define fn (LLVM-Add-Function mod "const_test" fn-type))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)

    (define c1 (LLVM-Const-Int i32 42 0))
    (define c2 (LLVM-Const-Real dbl 3.14))
    (define c3 (LLVM-Const-Null i32))
    (define c4 (LLVM-Const-All-Ones i32))
    (define c5 (LLVM-Get-Undef i32))

    (check-not-false c1)
    (check-not-false c2)
    (check-not-false c3)
    (check-not-false c4)
    (check-not-false c5)

    (LLVM-Build-Ret bld c1)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "ret i32 42")))

  (test-case "aggregate constants"
    (define ctx (LLVM-Context-Create))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define i8  (LLVM-Int8-Type-In-Context ctx))

    ;; Const string
    (define cs (LLVM-Const-String-In-Context ctx "hello" 5 0))
    (check-not-false cs)

    ;; Const array
    (define elts (list (LLVM-Const-Int i32 1 0)
                       (LLVM-Const-Int i32 2 0)
                       (LLVM-Const-Int i32 3 0)))
    (define ca (LLVM-Const-Array i32 elts 3))
    (check-not-false ca)

    ;; Const struct (anonymous)
    (define cstruct (LLVM-Const-Struct (list (LLVM-Const-Int i32 10 0)
                                             (LLVM-Const-Int i32 20 0))
                                       2 0))
    (check-not-false cstruct)

    ;; Const named struct
    (define pair-ty (LLVM-Struct-Create-Named ctx "pair"))
    (LLVM-Struct-Set-Body pair-ty (list i32 i32) 2 0)
    (define cnamed (LLVM-Const-Named-Struct pair-ty
                     (list (LLVM-Const-Int i32 1 0)
                           (LLVM-Const-Int i32 2 0))
                     2))
    (check-not-false cnamed))

  (test-case "global variables in IR"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "globals" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    (define g (LLVM-Add-Global mod i32 "my_global"))
    (check-not-false g)
    (LLVM-Set-Initializer g (LLVM-Const-Int i32 42 0))
    (LLVM-Set-Global-Constant g 1)
    (LLVM-Set-Alignment g 4)

    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "@my_global"))
    (check-true (string-contains? ir "constant"))
    (check-true (string-contains? ir "42")))

  (test-case "linkage and visibility"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "linkage" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    (define g (LLVM-Add-Global mod i32 "g"))
    (LLVM-Set-Linkage g 'LLVMInternalLinkage)
    (check-equal? (LLVM-Get-Linkage g) 'LLVMInternalLinkage)

    (LLVM-Set-Visibility g 'LLVMHiddenVisibility)
    (check-equal? (LLVM-Get-Visibility g) 'LLVMHiddenVisibility))

  (test-case "JIT: function reads global constant"
    ;; Build: @g = constant i32 42
    ;;        define i32 @read_g() { ret i32 load(@g) }
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "gread" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    (define g (LLVM-Add-Global mod i32 "g"))
    (LLVM-Set-Initializer g (LLVM-Const-Int i32 42 0))
    (LLVM-Set-Global-Constant g 1)

    (define fn (LLVM-Add-Function mod "read_g"
                 (LLVM-Function-Type i32 '() 0 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld (LLVM-Build-Load2 bld i32 g "val"))

    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (define f (cast (LLVM-Get-Function-Address ee "read_g")
                    _uint64 (_fun -> _int32)))
    (check-equal? (f) 42)))
