#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide LLVM-Create-Disasm
         LLVM-Disasm-Dispose
         LLVM-Set-Disasm-Options
         LLVM-Disasm-Instruction)

;; LLVMDisasmContextRef is an opaque pointer.
(define _LLVM-Disasm-Context-Ref _pointer)

;; ---- Create / Dispose ------------------------------------------------------

;; LLVMCreateDisasmCPU(Triple, CPU, DisInfo, TagType, GetOpInfo, SymbolLookUp)
;; We pass NULL for DisInfo, 0 for TagType, NULL for both callbacks.
;; This gives basic disassembly without symbolic annotation.
(define LLVMCreateDisasmCPU-raw
  (get-ffi-obj "LLVMCreateDisasmCPU" llvm-lib
               (_fun _string _string _pointer _int _pointer _pointer
                     -> _LLVM-Disasm-Context-Ref)))

(define LLVMDisasmDispose-raw
  (get-ffi-obj "LLVMDisasmDispose" llvm-lib
               (_fun _LLVM-Disasm-Context-Ref -> _void)))

;; Wrapped with allocator/deallocator for GC management.
(define LLVM-Disasm-Dispose
  ((deallocator) LLVMDisasmDispose-raw))

(define register-disasm!
  (make-register-allocation LLVM-Disasm-Dispose))

;; Create a disassembler for the given triple.
;; Uses "generic" CPU and no callbacks (basic disassembly).
(define (LLVM-Create-Disasm triple)
  (define dc (LLVMCreateDisasmCPU-raw triple "generic" #f 0 #f #f))
  (unless dc
    (error 'LLVM-Create-Disasm "failed to create disassembler for ~a" triple))
  (register-disasm! dc)
  dc)

;; ---- Options ---------------------------------------------------------------

(define LLVMSetDisasmOptions-raw
  (get-ffi-obj "LLVMSetDisasmOptions" llvm-lib
               (_fun _LLVM-Disasm-Context-Ref _uint64 -> _int)))

(define (LLVM-Set-Disasm-Options dc options)
  (LLVMSetDisasmOptions-raw dc options))

;; ---- Disassemble -----------------------------------------------------------

;; LLVMDisasmInstruction(DC, Bytes, BytesSize, PC, OutString, OutStringSize)
;; Returns number of bytes consumed (0 = couldn't decode).
(define LLVMDisasmInstruction-raw
  (get-ffi-obj "LLVMDisasmInstruction" llvm-lib
               (_fun _LLVM-Disasm-Context-Ref
                     _pointer        ; uint8_t* Bytes
                     _uint64         ; BytesSize
                     _uint64         ; PC
                     _pointer        ; char* OutString
                     _size           ; OutStringSize
                     -> _size)))

;; Disassemble one instruction from a byte string or pointer.
;; Returns (values instruction-string bytes-consumed) on success,
;; or (values #f 0) if the bytes couldn't be decoded.
;; bytes-or-ptr: bytes? or cpointer?
;; size: number of bytes available
;; pc: virtual address for the instruction (used in relative calculations)
(define (LLVM-Disasm-Instruction dc bytes-or-ptr size pc)
  (define out-size 256)
  (define out-buf (malloc out-size 'atomic))
  (define input-ptr
    (cond
      [(bytes? bytes-or-ptr)
       (define p (malloc size 'atomic))
       (memcpy p bytes-or-ptr size)
       p]
      [else bytes-or-ptr]))
  (define consumed
    (LLVMDisasmInstruction-raw dc input-ptr size pc out-buf out-size))
  (if (zero? consumed)
      (values #f 0)
      (values (cast out-buf _pointer _string) consumed)))
