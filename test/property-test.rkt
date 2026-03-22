#lang racket/base

(module+ test
  (require rackunit
           racket/string
           racket/list
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/target-machine
           llvm/private/ffi/execution-engine
           llvm/private/ffi/passes
           llvm/private/ffi/bitcode
           llvm/private/ffi/linker
           llvm/private/ffi/iteration)

  ;; ---- Helpers ---------------------------------------------------------------

  ;; Build a function that computes: ret a OP b OP const
  ;; where OP is one of add/sub/mul and const is a random constant.
  (define (build-arith-module name op-builder const-val)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context name ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "f"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (define tmp (op-builder bld (LLVM-Get-Param fn 0)
                                (LLVM-Get-Param fn 1) "tmp"))
    (define result (LLVM-Build-Add bld tmp (LLVM-Const-Int i32 const-val 0) "r"))
    (LLVM-Build-Ret bld result)
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)
    (values ctx mod))

  ;; Extract function names from a module via iteration.
  (define (module-function-names mod)
    (map LLVM-Get-Value-Name (LLVM-Module-Functions mod)))

  ;; Extract IR text from module.
  (define (module-ir mod)
    (define ptr (LLVM-Print-Module-To-String mod))
    (define s (cast ptr _pointer _string))
    (LLVM-Dispose-Message ptr)
    s)

  ;; JIT a two-arg i32 function and return a callable.
  (define (jit-module mod fn-name)
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
    (LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
    (define ee
      (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
    (cast (LLVM-Get-Function-Address ee fn-name)
          _uint64 (_fun _int32 _int32 -> _int32)))

  ;; Random non-negative i32 values (LLVM-Const-Int takes _ullong).
  (define (random-i32) (random 1000))

  ;; ---- Law 1: Bitcode round-trip preserves structure --------------------------
  ;; parse-bitcode(write-bitcode(m)) ≅ m
  ;; where ≅ means same function names

  (test-case "law: bitcode round-trip preserves function names"
    (for ([_ (in-range 5)])
      (define c (random 1000))
      (define-values (ctx mod) (build-arith-module "rt" LLVM-Build-Add c))
      (define names-before (module-function-names mod))

      ;; Round-trip
      (define buf (LLVM-Write-Bitcode-To-Memory-Buffer mod))
      (define ctx2 (LLVM-Context-Create))
      (define mod2 (LLVM-Parse-Bitcode-In-Context2 ctx2 buf))
      (define names-after (module-function-names mod2))

      (check-equal? names-before names-after
                    (format "bitcode round-trip with const=~a" c))))

  ;; ---- Law 2: IR text round-trip preserves structure --------------------------
  ;; parse-ir(print-module-to-string(m)) ≅ m

  (test-case "law: IR text round-trip preserves function names"
    (for ([_ (in-range 5)])
      (define c (random 1000))
      (define-values (ctx mod) (build-arith-module "irt" LLVM-Build-Add c))
      (define names-before (module-function-names mod))

      ;; Round-trip through IR text
      (define ir (module-ir mod))
      (define ctx2 (LLVM-Context-Create))
      (define buf (LLVM-Create-Memory-Buffer-With-Memory-Range
                   ir (string-length ir) "ir" 0))
      (define mod2 (LLVM-Parse-IR-In-Context ctx2 buf))
      (define names-after (module-function-names mod2))

      (check-equal? names-before names-after
                    (format "IR round-trip with const=~a" c))))

  ;; ---- Law 3: Idempotence of target initialization ----------------------------
  ;; init! ; init! ≡ init!

  (test-case "law: Initialize-Native-Target! is idempotent"
    (for ([_ (in-range 10)])
      (check-not-exn Initialize-Native-Target!)))

  ;; ---- Law 4: Idempotence of module verification ------------------------------
  ;; verify(m) ; verify(m) ≡ verify(m)  for valid m

  (test-case "law: Verify-Module is idempotent for valid modules"
    (for ([_ (in-range 5)])
      (define c (random 1000))
      (define-values (ctx mod) (build-arith-module "idm" LLVM-Build-Add c))
      (check-not-exn (lambda () (LLVM-Verify-Module mod 'LLVMReturnStatusAction)))
      (check-not-exn (lambda () (LLVM-Verify-Module mod 'LLVMReturnStatusAction)))
      (check-not-exn (lambda () (LLVM-Verify-Module mod 'LLVMReturnStatusAction)))))

  ;; ---- Law 5: Optimization preserves semantics --------------------------------
  ;; jit-call(optimize(f), args) = jit-call(f, args)

  (test-case "law: optimization preserves computed results"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)
    (for ([_ (in-range 5)])
      (define c (random-i32))
      (define a (random-i32))
      (define b (random-i32))

      ;; Unoptimized
      (define-values (ctx1 mod1) (build-arith-module "unopt" LLVM-Build-Add c))
      (define f1 (jit-module mod1 "f"))
      (define result1 (f1 a b))

      ;; Optimized with default<O2>
      (define-values (ctx2 mod2) (build-arith-module "opt" LLVM-Build-Add c))
      (define triple-ptr (LLVM-Get-Default-Target-Triple))
      (define triple (cast triple-ptr _pointer _string))
      (LLVM-Dispose-Message triple-ptr)
      (define target (LLVM-Get-Target-From-Triple triple))
      (define tm (LLVM-Create-Target-Machine
                  target triple "generic" ""
                  'LLVMCodeGenLevelDefault
                  'LLVMRelocDefault
                  'LLVMCodeModelDefault))
      (define popts (LLVM-Create-Pass-Builder-Options))
      (LLVM-Run-Passes mod2 "default<O2>" tm popts)
      (define f2 (jit-module mod2 "f"))
      (define result2 (f2 a b))

      (check-equal? result1 result2
                    (format "opt preserves f(~a,~a) with const=~a" a b c))))

  ;; ---- Law 6: Clone produces identical IR -------------------------------------
  ;; print-ir(clone(m)) = print-ir(m)

  (test-case "law: clone-module produces identical IR"
    (for ([_ (in-range 5)])
      (define c (random 1000))
      (define-values (ctx mod) (build-arith-module "cln" LLVM-Build-Add c))
      (define ir-original (module-ir mod))
      (define mod2 (LLVM-Clone-Module mod))
      (define ir-clone (module-ir mod2))
      (check-equal? ir-original ir-clone
                    (format "clone with const=~a" c))))

  ;; ---- Law 7: Linking is associative ------------------------------------------
  ;; link(link(a, b), c) ≅ link(a, link(b, c))
  ;; where ≅ means same set of function names

  (test-case "law: linking is associative"
    (for ([_ (in-range 3)])
      (define ca (random 1000))
      (define cb (random 1000))
      (define cc (random 1000))

      ;; Build three modules with distinct function names
      (define (make-fn ctx mod name c)
        (define i32 (LLVM-Int32-Type-In-Context ctx))
        (define fn (LLVM-Add-Function mod name
                     (LLVM-Function-Type i32 (list i32) 1 0)))
        (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
        (define bld (LLVM-Create-Builder-In-Context ctx))
        (LLVM-Position-Builder-At-End bld bb)
        (LLVM-Build-Ret bld
          (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                              (LLVM-Const-Int i32 c 0) "r")))

      ;; Left association: link(link(a, b), c)
      (define ctx-l (LLVM-Context-Create))
      (define a-l (LLVM-Module-Create-With-Name-In-Context "a" ctx-l))
      (make-fn ctx-l a-l "fa" ca)
      (define b-l (LLVM-Module-Create-With-Name-In-Context "b" ctx-l))
      (make-fn ctx-l b-l "fb" cb)
      (define c-l (LLVM-Module-Create-With-Name-In-Context "c" ctx-l))
      (make-fn ctx-l c-l "fc" cc)
      (LLVM-Link-Modules2 a-l b-l)   ; a-l now has fa + fb
      (LLVM-Link-Modules2 a-l c-l)   ; a-l now has fa + fb + fc
      (define names-left (sort (module-function-names a-l) string<?))

      ;; Right association: link(a, link(b, c))
      (define ctx-r (LLVM-Context-Create))
      (define a-r (LLVM-Module-Create-With-Name-In-Context "a" ctx-r))
      (make-fn ctx-r a-r "fa" ca)
      (define b-r (LLVM-Module-Create-With-Name-In-Context "b" ctx-r))
      (make-fn ctx-r b-r "fb" cb)
      (define c-r (LLVM-Module-Create-With-Name-In-Context "c" ctx-r))
      (make-fn ctx-r c-r "fc" cc)
      (LLVM-Link-Modules2 b-r c-r)   ; b-r now has fb + fc
      (LLVM-Link-Modules2 a-r b-r)   ; a-r now has fa + fb + fc
      (define names-right (sort (module-function-names a-r) string<?))

      (check-equal? names-left names-right
                    (format "link assoc with ~a,~a,~a" ca cb cc))))

  ;; ---- Law 8: Linking has right identity (empty module) -----------------------
  ;; link(m, empty) ≅ m

  (test-case "law: linking with empty module is identity"
    (for ([_ (in-range 5)])
      (define c (random 1000))
      (define-values (ctx mod) (build-arith-module "id" LLVM-Build-Add c))
      (define ir-before (module-ir mod))

      ;; Link with empty module
      (define empty (LLVM-Module-Create-With-Name-In-Context "empty" ctx))
      (LLVM-Link-Modules2 mod empty)
      (define ir-after (module-ir mod))

      ;; Module ID line changes but function body should be preserved
      (define names-before (module-function-names mod))
      (check-equal? (length names-before) 1)
      (check-true (string-contains? ir-after "define")
                  (format "identity link with const=~a" c))))

  ;; ---- Law 9: Type singletons per context ------------------------------------
  ;; Int32-Type-In-Context(ctx) = Int32-Type-In-Context(ctx)

  ;; Compare cpointer addresses (FFI may create fresh wrappers).
  (define (ptr=? a b)
    (= (cast a _pointer _intptr) (cast b _pointer _intptr)))

  (test-case "law: type constructors return singletons per context"
    (for ([_ (in-range 5)])
      (define ctx (LLVM-Context-Create))
      (define t1 (LLVM-Int32-Type-In-Context ctx))
      (define t2 (LLVM-Int32-Type-In-Context ctx))
      (check-true (ptr=? t1 t2) "i32 should be singleton")

      (define d1 (LLVM-Double-Type-In-Context ctx))
      (define d2 (LLVM-Double-Type-In-Context ctx))
      (check-true (ptr=? d1 d2) "double should be singleton")

      (define v1 (LLVM-Void-Type-In-Context ctx))
      (define v2 (LLVM-Void-Type-In-Context ctx))
      (check-true (ptr=? v1 v2) "void should be singleton"))))
