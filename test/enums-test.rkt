#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/enums)

  (test-case "verifier failure action enum values"
    (check-equal? (cast 'LLVMAbortProcessAction _LLVM-Verifier-Failure-Action _int) 0)
    (check-equal? (cast 'LLVMPrintMessageAction _LLVM-Verifier-Failure-Action _int) 1)
    (check-equal? (cast 'LLVMReturnStatusAction _LLVM-Verifier-Failure-Action _int) 2))

  (test-case "code gen opt level enum values"
    (check-equal? (cast 'LLVMCodeGenLevelNone _LLVM-Code-Gen-Opt-Level _int) 0)
    (check-equal? (cast 'LLVMCodeGenLevelAggressive _LLVM-Code-Gen-Opt-Level _int) 3))

  (test-case "code model enum values"
    (check-equal? (cast 'LLVMCodeModelDefault _LLVM-Code-Model _int) 0)
    (check-equal? (cast 'LLVMCodeModelJITDefault _LLVM-Code-Model _int) 1))

  (test-case "reloc mode enum values"
    (check-equal? (cast 'LLVMRelocDefault _LLVM-Reloc-Mode _int) 0)
    (check-equal? (cast 'LLVMRelocPIC _LLVM-Reloc-Mode _int) 2)))
