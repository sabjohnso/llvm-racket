#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "enums.rkt")

(provide LLVM-Create-DI-Builder
         LLVM-Dispose-DI-Builder
         LLVM-DI-Builder-Finalize
         LLVM-DI-Builder-Create-File
         LLVM-DI-Builder-Create-Compile-Unit
         LLVM-DI-Builder-Create-Function
         LLVM-DI-Builder-Create-Lexical-Block
         LLVM-DI-Builder-Create-Basic-Type
         LLVM-DI-Builder-Create-Subroutine-Type
         LLVM-DI-Builder-Create-Debug-Location
         LLVM-Set-Subprogram
         LLVM-Set-Current-Debug-Location2)

;; ---- DIBuilder create / dispose --------------------------------------------

(define-llvm LLVM-Dispose-DI-Builder
  (_fun _LLVM-DI-Builder-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-DI-Builder
  (_fun _LLVM-Module-Ref -> _LLVM-DI-Builder-Ref)
  #:wrap (allocator/prevent-gc LLVM-Dispose-DI-Builder 0))

(define-llvm LLVM-DI-Builder-Finalize
  (_fun _LLVM-DI-Builder-Ref -> _void))

;; ---- File and Compile Unit -------------------------------------------------

(define-llvm LLVM-DI-Builder-Create-File
  (_fun _LLVM-DI-Builder-Ref
        _string _size     ; filename, filename-len
        _string _size     ; directory, directory-len
        -> _LLVM-Metadata-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (dib filename directory)
               (proc dib filename (string-length filename)
                     directory (string-length directory))))))

(define-llvm LLVM-DI-Builder-Create-Compile-Unit
  (_fun _LLVM-DI-Builder-Ref
        _LLVM-DWARF-Source-Language
        _LLVM-Metadata-Ref         ; file
        _string _size              ; producer, producer-len
        _LLVM-Bool                 ; isOptimized
        _string _size              ; flags, flags-len
        _uint                      ; runtimeVer
        _string _size              ; splitName, splitName-len
        _LLVM-DWARF-Emission-Kind
        _uint                      ; DWOId
        _LLVM-Bool                 ; splitDebugInlining
        _LLVM-Bool                 ; debugInfoForProfiling
        _string _size              ; sysroot, sysroot-len
        _string _size              ; SDK, SDK-len
        -> _LLVM-Metadata-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (dib lang file producer is-optimized flags
                      runtime-ver split-name emission-kind dwo-id
                      split-debug-inlining debug-info-for-profiling)
               (proc dib lang file
                     producer (string-length producer)
                     is-optimized
                     flags (string-length flags)
                     runtime-ver
                     split-name (string-length split-name)
                     emission-kind dwo-id
                     split-debug-inlining
                     debug-info-for-profiling
                     "" 0   ; sysroot
                     "" 0)))))  ; SDK

;; ---- Function and Scope ----------------------------------------------------

(define-llvm LLVM-DI-Builder-Create-Function
  (_fun _LLVM-DI-Builder-Ref
        _LLVM-Metadata-Ref         ; scope
        _string _size              ; name, name-len
        _string _size              ; linkage-name, linkage-name-len
        _LLVM-Metadata-Ref         ; file
        _uint                      ; line
        _LLVM-Metadata-Ref         ; type (subroutine type)
        _LLVM-Bool                 ; isLocalToUnit
        _LLVM-Bool                 ; isDefinition
        _uint                      ; scopeLine
        _uint                      ; flags (LLVMDIFlags)
        _LLVM-Bool                 ; isOptimized
        -> _LLVM-Metadata-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (dib scope name linkage-name file line type
                      is-local is-definition scope-line flags is-optimized)
               (proc dib scope
                     name (string-length name)
                     linkage-name (string-length linkage-name)
                     file line type
                     is-local is-definition scope-line flags is-optimized)))))

(define-llvm LLVM-DI-Builder-Create-Lexical-Block
  (_fun _LLVM-DI-Builder-Ref
        _LLVM-Metadata-Ref         ; scope
        _LLVM-Metadata-Ref         ; file
        _uint                      ; line
        _uint                      ; column
        -> _LLVM-Metadata-Ref))

;; ---- Debug Types -----------------------------------------------------------

(define-llvm LLVM-DI-Builder-Create-Basic-Type
  (_fun _LLVM-DI-Builder-Ref
        _string _size              ; name, name-len
        _uint64                    ; sizeInBits
        _uint                      ; encoding (DW_ATE_*)
        _uint                      ; flags (LLVMDIFlags)
        -> _LLVM-Metadata-Ref)
  #:wrap (let ()
           (lambda (proc)
             (lambda (dib name size-in-bits encoding flags)
               (proc dib name (string-length name) size-in-bits encoding flags)))))

(define-llvm LLVM-DI-Builder-Create-Subroutine-Type
  (_fun _LLVM-DI-Builder-Ref
        _LLVM-Metadata-Ref         ; file
        (_list i _LLVM-Metadata-Ref) ; parameter types (first = return type)
        _uint                      ; num parameters
        _uint                      ; flags (LLVMDIFlags)
        -> _LLVM-Metadata-Ref))

;; ---- Debug Location --------------------------------------------------------

(define-llvm LLVM-DI-Builder-Create-Debug-Location
  (_fun _LLVM-Context-Ref
        _uint                      ; line
        _uint                      ; column
        _LLVM-Metadata-Ref         ; scope
        _LLVM-Metadata-Ref/null    ; inlinedAt (nullable)
        -> _LLVM-Metadata-Ref))

;; ---- Attach debug info to IR -----------------------------------------------

(define-llvm LLVM-Set-Subprogram
  (_fun _LLVM-Value-Ref _LLVM-Metadata-Ref -> _void))

(define-llvm LLVM-Set-Current-Debug-Location2
  (_fun _LLVM-Builder-Ref _LLVM-Metadata-Ref -> _void))
