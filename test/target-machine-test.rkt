#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           racket/string
           racket/file
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
    (check-equal? result 'failed "should fail for invalid triple"))

  ;; Helper: build an add(i32,i32)->i32 module and return (values ctx mod tm)
  ;; Caller must dispose tm, mod, ctx in that order (unless mod ownership transfers).
  (define (build-add-module)
    (Initialize-Native-Target!)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "emit-test" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
    (define fn (LLVM-Add-Function mod "add" fn-type))
    (define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define builder (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End builder entry)
    (LLVM-Build-Ret builder
                    (LLVM-Build-Add builder
                                   (LLVM-Get-Param fn 0)
                                   (LLVM-Get-Param fn 1)
                                   "tmp"))
    (LLVM-Dispose-Builder builder)

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define-values (_f? target _e?) (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))
    (values ctx mod tm))

  (test-case "emit module as assembly to memory buffer"
    (define-values (ctx mod tm) (build-add-module))

    (define-values (failed? buf err)
      (LLVM-Target-Machine-Emit-To-Memory-Buffer tm mod 'LLVMAssemblyFile))
    (check-equal? failed? 0
                  (if (and (not (zero? failed?)) err)
                      (let ([msg (cast err _pointer _string)])
                        (LLVM-Dispose-Message err)
                        msg)
                      "emit failed"))

    (define asm-ptr (LLVM-Get-Buffer-Start buf))
    (define asm-len (LLVM-Get-Buffer-Size buf))
    (define asm (cast asm-ptr _pointer _string))
    (check-true (> asm-len 0) "assembly should be non-empty")
    (check-true (string-contains? asm "add") "assembly should contain 'add'")

    (LLVM-Dispose-Memory-Buffer buf)
    (LLVM-Dispose-Target-Machine tm)
    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx))

  (test-case "emit module as assembly to file"
    (define-values (ctx mod tm) (build-add-module))
    (define tmp-path (make-temporary-file "llvm-test-~a.s"))

    (define-values (failed? err)
      (LLVM-Target-Machine-Emit-To-File tm mod (path->string tmp-path) 'LLVMAssemblyFile))
    (check-equal? failed? 0
                  (if (and (not (zero? failed?)) err)
                      (let ([msg (cast err _pointer _string)])
                        (LLVM-Dispose-Message err)
                        msg)
                      "emit to file failed"))

    (define asm (file->string tmp-path))
    (check-true (> (string-length asm) 0) "file should be non-empty")
    (check-true (string-contains? asm "add") "file should contain 'add'")

    (delete-file tmp-path)
    (LLVM-Dispose-Target-Machine tm)
    (LLVM-Dispose-Module mod)
    (LLVM-Context-Dispose ctx)))
