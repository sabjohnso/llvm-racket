llvm
====

LLVM bindings for Racket via the LLVM C API.

All resources are GC-managed — no manual `Dispose` calls needed.

## Installation

```sh
raco pkg install --link --name llvm
```

## Usage

```racket
(require llvm/unsafe ffi/unsafe)

;; Initialize LLVM
(Initialize-Native-Target!)
(LLVM-Link-In-MCJIT)

;; Build a function: i32 add(i32 a, i32 b) { return a + b; }
(define ctx (LLVM-Context-Create))
(define mod (LLVM-Module-Create-With-Name-In-Context "example" ctx))
(define i32 (LLVM-Int32-Type-In-Context ctx))
(define fn  (LLVM-Add-Function mod "add"
              (LLVM-Function-Type i32 (list i32 i32) 2 0)))
(define bb  (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
(define bld (LLVM-Create-Builder-In-Context ctx))
(LLVM-Position-Builder-At-End bld bb)
(LLVM-Build-Ret bld (LLVM-Build-Add bld
                                     (LLVM-Get-Param fn 0)
                                     (LLVM-Get-Param fn 1) "tmp"))

;; Verify and JIT compile
(LLVM-Verify-Module mod 'LLVMReturnStatusAction)
(define opts (make-LLVM-MCJIT-Compiler-Options 0 'LLVMCodeModelJITDefault 0 0 #f))
(LLVM-Initialize-MCJIT-Compiler-Options opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
(define ee
  (LLVM-Create-MCJIT-Compiler-For-Module mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

;; Call the JIT'd function
(define add-fn (cast (LLVM-Get-Function-Address ee "add")
                     _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4) ; => 7
```

## Documentation

```sh
raco docs llvm
```

## License

Dual-licensed under Apache 2.0 and MIT.
