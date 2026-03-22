llvm
====

LLVM bindings for Racket via the LLVM C API.

All resources are GC-managed — no manual `Dispose` calls needed.
Errors from LLVM are raised as Racket exceptions.

## Installation

```sh
raco pkg install --link --name llvm
```

## Usage (ORC JIT)

```racket
(require llvm/unsafe ffi/unsafe)

(Initialize-Native-Target!)

;; Build a function: i32 add(i32 a, i32 b) { return a + b; }
(define ts-ctx (LLVM-Orc-Create-New-Thread-Safe-Context))
(define ctx (LLVM-Orc-Thread-Safe-Context-Get-Context ts-ctx))
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

;; Verify, wrap, and JIT
(LLVM-Verify-Module mod 'LLVMReturnStatusAction)
(define ts-mod (LLVM-Orc-Create-New-Thread-Safe-Module mod ts-ctx))
(define jit (LLVM-Orc-Create-LLJIT #f))
(LLVM-Orc-LLJIT-Add-LLVM-IR-Module
 jit (LLVM-Orc-LLJIT-Get-Main-JIT-Dylib jit) ts-mod)

;; Call the JIT'd function
(define add-fn (cast (LLVM-Orc-LLJIT-Lookup jit "add")
                     _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4) ; => 7
```

## Documentation

```sh
raco docs llvm
```

## License

Dual-licensed under Apache 2.0 and MIT.
