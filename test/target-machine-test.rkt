#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/target
           llvm/private/ffi/target-machine)

  (test-case "get default triple and create target machine"
    (Initialize-Native-Target!)

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (check-true (string? triple))
    (check-true (> (string-length triple) 0))

    (define-values (failed? target err) (LLVM-Get-Target-From-Triple triple))
    (check-equal? failed? 0 "should find target for default triple")
    (when (and (not (zero? failed?)) err)
      (LLVM-Dispose-Message err))

    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelJITDefault))
    (check-not-false tm)
    (LLVM-Dispose-Target-Machine tm))

  (test-case "invalid triple produces error"
    (Initialize-Native-Target!)

    ;; LLVM-Get-Target-From-Triple returns a non-null _LLVM-Target-Ref on
    ;; success. On failure the target output is uninitialized (null), which
    ;; the cpointer type rejects. Use with-handlers to catch the FFI error
    ;; and verify the call did fail.
    (define result
      (with-handlers ([exn:fail? (λ (e) 'failed)])
        (define-values (failed? _target err) (LLVM-Get-Target-From-Triple "bogus-bogus-bogus"))
        (if (not (zero? failed?))
            (begin
              (when err (LLVM-Dispose-Message err))
              'failed)
            'succeeded)))
    (check-equal? result 'failed "should fail for invalid triple")))
