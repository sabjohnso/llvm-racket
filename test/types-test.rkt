#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/types)

  (test-case "opaque pointer types are defined"
    (check-true (ctype? _LLVM-Context-Ref))
    (check-true (ctype? _LLVM-Module-Ref))
    (check-true (ctype? _LLVM-Type-Ref))
    (check-true (ctype? _LLVM-Value-Ref))
    (check-true (ctype? _LLVM-Basic-Block-Ref))
    (check-true (ctype? _LLVM-Builder-Ref))
    (check-true (ctype? _LLVM-Execution-Engine-Ref))
    (check-true (ctype? _LLVM-Generic-Value-Ref))
    (check-true (ctype? _LLVM-Target-Ref))
    (check-true (ctype? _LLVM-Target-Machine-Ref)))

  (test-case "_LLVM-Bool is an integer type"
    (check-true (ctype? _LLVM-Bool))))
