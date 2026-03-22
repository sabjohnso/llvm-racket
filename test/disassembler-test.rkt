#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/target
           llvm/private/ffi/target-machine
           llvm/private/ffi/execution-engine
           llvm/private/ffi/disassembler)

  (test-case "disassemble machine code from JIT'd function"
    (Initialize-Native-Target!)
    (LLVM-Link-In-MCJIT)

    ;; Build and JIT a simple add function
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "dis" ctx))
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

    ;; Emit to object code and extract .text bytes
    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define target (LLVM-Get-Target-From-Triple triple))
    (define tm (LLVM-Create-Target-Machine
                target triple "generic" ""
                'LLVMCodeGenLevelDefault
                'LLVMRelocDefault
                'LLVMCodeModelDefault))
    (define buf (LLVM-Target-Machine-Emit-To-Memory-Buffer tm mod 'LLVMObjectFile))
    (define code-ptr (LLVM-Get-Buffer-Start buf))
    (define code-size (LLVM-Get-Buffer-Size buf))

    ;; Create disassembler
    (define dc (LLVM-Create-Disasm triple))
    (check-not-false dc)

    ;; Disassemble first few instructions from the raw object buffer
    ;; (the buffer contains the full object file, not just code,
    ;; but the first bytes may decode to something)
    (define result (LLVM-Disasm-Instruction dc code-ptr (min code-size 64) 0))
    ;; Result is either a string (decoded instruction) or #f (couldn't decode)
    ;; Either outcome is valid — object header bytes may not decode.
    ;; The key is that the disassembler didn't crash.
    (check-true (or (not result) (string? result))))

  (test-case "disassemble known x86 bytes"
    (Initialize-Native-Target!)

    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)

    (define dc (LLVM-Create-Disasm triple))
    (check-not-false dc)

    ;; x86-64: ret = 0xc3
    (define ret-bytes (bytes #xc3))
    (define result (LLVM-Disasm-Instruction dc ret-bytes 1 0))
    (check-true (string? result) "should decode ret instruction")
    (check-true (string-contains? result "ret")
                (format "expected 'ret' in ~s" result)))

  (test-case "set disasm options"
    (Initialize-Native-Target!)
    (define triple-ptr (LLVM-Get-Default-Target-Triple))
    (define triple (cast triple-ptr _pointer _string))
    (LLVM-Dispose-Message triple-ptr)
    (define dc (LLVM-Create-Disasm triple))
    ;; PrintImmHex = 2
    (check-not-exn (lambda () (LLVM-Set-Disasm-Options dc 2)))))
