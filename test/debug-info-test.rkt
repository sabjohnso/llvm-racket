#lang racket/base

(module+ test
  (require rackunit
           racket/string
           ffi/unsafe
           llvm/private/ffi/core
           llvm/private/ffi/analysis
           llvm/private/ffi/debug-info)

  (test-case "create debug info for a function"
    (define ctx (LLVM-Context-Create))
    (define mod (LLVM-Module-Create-With-Name-In-Context "dbg" ctx))
    (define i32 (LLVM-Int32-Type-In-Context ctx))

    ;; Create DIBuilder
    (define dib (LLVM-Create-DI-Builder mod))
    (check-not-false dib)

    ;; Create file
    (define file (LLVM-DI-Builder-Create-File dib "test.c" "src"))
    (check-not-false file)

    ;; Create compile unit
    (define cu (LLVM-DI-Builder-Create-Compile-Unit
                dib
                'LLVMDWARFSourceLanguageC  ; language
                file                       ; file
                "llvm-racket"              ; producer
                0                          ; isOptimized
                ""                         ; flags
                0                          ; runtimeVer
                ""                         ; splitName
                'LLVMDWARFEmissionFull     ; emissionKind
                0                          ; DWOId
                0                          ; splitDebugInlining
                0))                        ; debugInfoForProfiling
    (check-not-false cu)

    ;; Create basic type for i32
    (define di-i32 (LLVM-DI-Builder-Create-Basic-Type dib "int" 32 7 0))
    (check-not-false di-i32)

    ;; Create subroutine type: (i32, i32) -> i32
    (define sub-type (LLVM-DI-Builder-Create-Subroutine-Type
                      dib file (list di-i32 di-i32 di-i32) 3 0))
    (check-not-false sub-type)

    ;; Create function debug info
    (define di-fn (LLVM-DI-Builder-Create-Function
                   dib cu "add" "add" file 1 sub-type 0 1 1 0 0))
    (check-not-false di-fn)

    ;; Build the actual function
    (define fn (LLVM-Add-Function mod "add"
                 (LLVM-Function-Type i32 (list i32 i32) 2 0)))
    (LLVM-Set-Subprogram fn di-fn)

    ;; Create a debug location and set it on the builder
    (define loc (LLVM-DI-Builder-Create-Debug-Location ctx 2 0 di-fn #f))
    (check-not-false loc)

    (define bld (LLVM-Create-Builder-In-Context ctx))
    (define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
    (LLVM-Position-Builder-At-End bld bb)
    (LLVM-Set-Current-Debug-Location2 bld loc)
    (LLVM-Build-Ret bld
      (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                          (LLVM-Get-Param fn 1) "r"))

    ;; Finalize debug info
    (LLVM-DI-Builder-Finalize dib)

    ;; Verify module — should pass with debug info
    (LLVM-Verify-Module mod 'LLVMReturnStatusAction)

    ;; Check IR contains debug metadata
    (define ir-ptr (LLVM-Print-Module-To-String mod))
    (define ir (cast ir-ptr _pointer _string))
    (LLVM-Dispose-Message ir-ptr)
    (check-true (string-contains? ir "!dbg") "should contain debug metadata")
    (check-true (string-contains? ir "test.c") "should reference source file")))
