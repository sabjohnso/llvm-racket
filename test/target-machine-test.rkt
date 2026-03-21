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

    (define target (LLVM-Get-Target-From-Triple triple))
    (check-not-false target)

    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelJITDefault))
    (check-not-false tm))

  (test-case "invalid triple raises exn:fail"
    (Initialize-Native-Target!)
    (check-exn exn:fail?
               (lambda () (LLVM-Get-Target-From-Triple "bogus-bogus-bogus"))))

  ;; Helper: build an add(i32,i32)->i32 module and return (values ctx mod tm)
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

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))
    (values ctx mod tm))

  (test-case "emit module as assembly to memory buffer"
    (define-values (ctx mod tm) (build-add-module))

    (define buf (LLVM-Target-Machine-Emit-To-Memory-Buffer tm mod 'LLVMAssemblyFile))
    (define asm (cast (LLVM-Get-Buffer-Start buf) _pointer _string))
    (define asm-len (LLVM-Get-Buffer-Size buf))
    (check-true (> asm-len 0) "assembly should be non-empty")
    (check-true (string-contains? asm "add") "assembly should contain 'add'"))

  (test-case "emit module as assembly to file"
    (define-values (ctx mod tm) (build-add-module))
    (define tmp-path (make-temporary-file "llvm-test-~a.s"))

    (LLVM-Target-Machine-Emit-To-File tm mod (path->string tmp-path) 'LLVMAssemblyFile)

    (define asm (file->string tmp-path))
    (check-true (> (string-length asm) 0) "file should be non-empty")
    (check-true (string-contains? asm "add") "file should contain 'add'")
    (delete-file tmp-path)))
