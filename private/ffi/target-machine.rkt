#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt"
         "enums.rkt"
         "core.rkt")

(provide LLVM-Get-Default-Target-Triple
         LLVM-Get-Target-From-Triple
         LLVM-Create-Target-Machine
         LLVM-Dispose-Target-Machine
         LLVM-Target-Machine-Emit-To-Memory-Buffer
         LLVM-Target-Machine-Emit-To-File)

(define-llvm LLVM-Get-Default-Target-Triple
  (_fun -> _pointer)
  #:wrap (allocator LLVM-Dispose-Message))

(define-llvm LLVM-Get-Target-From-Triple
  (_fun _string
        (target : (_ptr o _LLVM-Target-Ref))
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result target err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (triple)
               (define-values (result target err) (proc triple))
               (check-llvm-error 'LLVM-Get-Target-From-Triple result err)
               target))))

(define-llvm LLVM-Dispose-Target-Machine
  (_fun _LLVM-Target-Machine-Ref -> _void)
  #:wrap (deallocator))

(define-llvm LLVM-Create-Target-Machine
  (_fun _LLVM-Target-Ref            ; target
        _string                     ; triple
        _string                     ; cpu
        _string                     ; features
        _LLVM-Code-Gen-Opt-Level    ; opt level
        _LLVM-Reloc-Mode            ; reloc mode
        _LLVM-Code-Model            ; code model
        -> _LLVM-Target-Machine-Ref)
  #:wrap (allocator LLVM-Dispose-Target-Machine))

;; Register out-param buffer with the allocator mechanism.
(define register-memory-buffer!
  (make-register-allocation LLVM-Dispose-Memory-Buffer))

;; Emit module as assembly or object code to a memory buffer.
;; Raises exn:fail on error.  Returns the memory buffer on success.
(define-llvm LLVM-Target-Machine-Emit-To-Memory-Buffer
  (_fun _LLVM-Target-Machine-Ref
        _LLVM-Module-Ref
        _LLVM-Code-Gen-File-Type
        (err : (_ptr o _pointer))
        (buf : (_ptr o _LLVM-Memory-Buffer-Ref))
        -> (result : _LLVM-Bool)
        -> (values result buf err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (tm mod file-type)
               (define-values (result buf err) (proc tm mod file-type))
               (check-llvm-error 'LLVM-Target-Machine-Emit-To-Memory-Buffer result err)
               (register-memory-buffer! buf)
               buf))))

;; Emit module as assembly or object code to a file.
;; Raises exn:fail on error.
(define-llvm LLVM-Target-Machine-Emit-To-File
  (_fun _LLVM-Target-Machine-Ref
        _LLVM-Module-Ref
        _string
        _LLVM-Code-Gen-File-Type
        (err : (_ptr o _pointer))
        -> (result : _LLVM-Bool)
        -> (values result err))
  #:wrap (let ()
           (lambda (proc)
             (lambda (tm mod filename file-type)
               (define-values (result err) (proc tm mod filename file-type))
               (check-llvm-error 'LLVM-Target-Machine-Emit-To-File result err)))))
