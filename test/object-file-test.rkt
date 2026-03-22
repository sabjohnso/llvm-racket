#lang racket/base

(module+ test
  (require rackunit
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/target-machine
           llvm/private/ffi/object-file
           llvm/private/ffi/bitcode)

  ;; Helper: build a simple add module and emit as object code buffer
  (define (build-object-buffer)
    (Initialize-Native-Target!)
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "obj" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))
    (define fn (LLVM-Add-Function mod "add"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (define bld (LLVM-Create-Builder-In-Context ctx))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Build-Ret bld
      (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                          (LLVM-Get-Param fn 1) "r"))
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))
    (LLVM-Target-Machine-Emit-To-Memory-Buffer tm mod 'LLVMObjectFile))

  (test-case "create object file and inspect sections"
    (define buf (build-object-buffer))
    (define obj (LLVM-Create-Object-File buf))
    (check-not-false obj)

    ;; Should have at least one section (.text)
    (define sections (LLVM-Object-File-Sections obj))
    (check-true (> (length sections) 0) "should have sections")

    ;; Each section has a name and size
    (for ([s (in-list sections)])
      (check-true (string? (section-info-name s)))
      (check-true (exact-nonnegative-integer? (section-info-size s)))))

  (test-case "create object file and inspect symbols"
    (define buf (build-object-buffer))
    (define obj (LLVM-Create-Object-File buf))

    (define symbols (LLVM-Object-File-Symbols obj))
    ;; Should have "add" symbol
    (define names (map symbol-info-name symbols))
    (check-true (ormap (lambda (n) (and (string? n) (regexp-match? #rx"add" n)))
                       names)
                "should contain 'add' symbol"))

  (test-case "iterate relocations for each section"
    (define buf (build-object-buffer))
    (define obj (LLVM-Create-Object-File buf))

    ;; Walk sections with low-level API and collect relocations
    (define sec-iter (LLVM-Get-Sections obj))
    (let loop ()
      (unless (not (zero? (LLVM-Is-Section-Iterator-At-End obj sec-iter)))
        (define relocs (LLVM-Section-Relocations sec-iter))
        ;; Each relocation should be a relocation-info struct
        (for ([r (in-list relocs)])
          (check-true (exact-nonnegative-integer? (relocation-info-offset r)))
          (check-true (exact-nonnegative-integer? (relocation-info-type r)))
          (check-true (string? (relocation-info-type-name r))))
        (LLVM-Move-To-Next-Section sec-iter)
        (loop)))
    (LLVM-Dispose-Section-Iterator sec-iter))

  (test-case "invalid object file raises"
    (define buf (LLVM-Create-Memory-Buffer-With-Memory-Range
                 "not an object file" 18 "bad" 0))
    (check-exn exn:fail?
               (lambda () (LLVM-Create-Object-File buf)))))
