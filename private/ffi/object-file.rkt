#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt"
         "types.rkt")

(provide ;; Object file
         LLVM-Create-Object-File
         LLVM-Dispose-Object-File
         ;; Section iteration (low-level)
         LLVM-Get-Sections
         LLVM-Dispose-Section-Iterator
         LLVM-Is-Section-Iterator-At-End
         LLVM-Move-To-Next-Section
         LLVM-Get-Section-Name
         LLVM-Get-Section-Size
         LLVM-Get-Section-Contents
         LLVM-Get-Section-Address
         ;; Symbol iteration (low-level)
         LLVM-Get-Symbols
         LLVM-Dispose-Symbol-Iterator
         LLVM-Is-Symbol-Iterator-At-End
         LLVM-Move-To-Next-Symbol
         LLVM-Get-Symbol-Name
         LLVM-Get-Symbol-Address
         LLVM-Get-Symbol-Size
         ;; Relocation iteration (low-level)
         LLVM-Get-Relocations
         LLVM-Dispose-Relocation-Iterator
         LLVM-Is-Relocation-Iterator-At-End
         LLVM-Move-To-Next-Relocation
         LLVM-Get-Relocation-Offset
         LLVM-Get-Relocation-Type
         LLVM-Get-Relocation-Type-Name
         LLVM-Get-Relocation-Value-String
         ;; Racket-idiomatic helpers
         (struct-out section-info)
         (struct-out symbol-info)
         LLVM-Object-File-Sections
         LLVM-Object-File-Symbols)

;; ---- Object File -----------------------------------------------------------

(define-llvm LLVM-Dispose-Object-File
  (_fun _LLVM-Object-File-Ref -> _void)
  #:wrap (deallocator))

;; LLVMCreateObjectFile consumes the memory buffer.
(define-llvm LLVM-Create-Object-File
  (_fun _LLVM-Memory-Buffer-Ref -> _LLVM-Object-File-Ref/null)
  #:wrap (let ()
           (define wrap (allocator LLVM-Dispose-Object-File))
           (lambda (proc)
             (define wrapped (wrap proc))
             (lambda (buf)
               (define result (wrapped buf))
               (unless result
                 (error 'LLVM-Create-Object-File "failed to create object file"))
               result))))

;; ---- Section Iteration (low-level) ----------------------------------------

(define-llvm LLVM-Get-Sections
  (_fun _LLVM-Object-File-Ref -> _LLVM-Section-Iterator-Ref))

(define-llvm LLVM-Dispose-Section-Iterator
  (_fun _LLVM-Section-Iterator-Ref -> _void))

(define-llvm LLVM-Is-Section-Iterator-At-End
  (_fun _LLVM-Object-File-Ref _LLVM-Section-Iterator-Ref -> _LLVM-Bool))

(define-llvm LLVM-Move-To-Next-Section
  (_fun _LLVM-Section-Iterator-Ref -> _void))

;; May return #f for sections with no name.
(define-llvm LLVM-Get-Section-Name
  (_fun _LLVM-Section-Iterator-Ref -> _pointer)
  #:wrap (let ()
           (lambda (proc)
             (lambda (si)
               (define p (proc si))
               (if p (cast p _pointer _string) "")))))

(define-llvm LLVM-Get-Section-Size
  (_fun _LLVM-Section-Iterator-Ref -> _uint64))

(define-llvm LLVM-Get-Section-Contents
  (_fun _LLVM-Section-Iterator-Ref -> _pointer))

(define-llvm LLVM-Get-Section-Address
  (_fun _LLVM-Section-Iterator-Ref -> _uint64))

;; ---- Symbol Iteration (low-level) -----------------------------------------

(define-llvm LLVM-Get-Symbols
  (_fun _LLVM-Object-File-Ref -> _LLVM-Symbol-Iterator-Ref))

(define-llvm LLVM-Dispose-Symbol-Iterator
  (_fun _LLVM-Symbol-Iterator-Ref -> _void))

(define-llvm LLVM-Is-Symbol-Iterator-At-End
  (_fun _LLVM-Object-File-Ref _LLVM-Symbol-Iterator-Ref -> _LLVM-Bool))

(define-llvm LLVM-Move-To-Next-Symbol
  (_fun _LLVM-Symbol-Iterator-Ref -> _void))

(define-llvm LLVM-Get-Symbol-Name
  (_fun _LLVM-Symbol-Iterator-Ref -> _string))

(define-llvm LLVM-Get-Symbol-Address
  (_fun _LLVM-Symbol-Iterator-Ref -> _uint64))

(define-llvm LLVM-Get-Symbol-Size
  (_fun _LLVM-Symbol-Iterator-Ref -> _uint64))

;; ---- Relocation Iteration (low-level) -------------------------------------

(define-llvm LLVM-Get-Relocations
  (_fun _LLVM-Section-Iterator-Ref -> _LLVM-Relocation-Iterator-Ref))

(define-llvm LLVM-Dispose-Relocation-Iterator
  (_fun _LLVM-Relocation-Iterator-Ref -> _void))

(define-llvm LLVM-Is-Relocation-Iterator-At-End
  (_fun _LLVM-Section-Iterator-Ref _LLVM-Relocation-Iterator-Ref -> _LLVM-Bool))

(define-llvm LLVM-Move-To-Next-Relocation
  (_fun _LLVM-Relocation-Iterator-Ref -> _void))

(define-llvm LLVM-Get-Relocation-Offset
  (_fun _LLVM-Relocation-Iterator-Ref -> _uint64))

(define-llvm LLVM-Get-Relocation-Type
  (_fun _LLVM-Relocation-Iterator-Ref -> _uint64))

(define-llvm LLVM-Get-Relocation-Type-Name
  (_fun _LLVM-Relocation-Iterator-Ref -> _string))

(define-llvm LLVM-Get-Relocation-Value-String
  (_fun _LLVM-Relocation-Iterator-Ref -> _string))

;; ---- Racket-idiomatic helpers ----------------------------------------------

(struct section-info (name size address) #:transparent)
(struct symbol-info (name address size) #:transparent)

;; Collect all sections into a list of section-info structs.
(define (LLVM-Object-File-Sections obj)
  (define iter (LLVM-Get-Sections obj))
  (let loop ([acc '()])
    (cond
      [(not (zero? (LLVM-Is-Section-Iterator-At-End obj iter)))
       (LLVM-Dispose-Section-Iterator iter)
       (reverse acc)]
      [else
       (define info (section-info (LLVM-Get-Section-Name iter)
                                 (LLVM-Get-Section-Size iter)
                                 (LLVM-Get-Section-Address iter)))
       (LLVM-Move-To-Next-Section iter)
       (loop (cons info acc))])))

;; Collect all symbols into a list of symbol-info structs.
(define (LLVM-Object-File-Symbols obj)
  (define iter (LLVM-Get-Symbols obj))
  (let loop ([acc '()])
    (cond
      [(not (zero? (LLVM-Is-Symbol-Iterator-At-End obj iter)))
       (LLVM-Dispose-Symbol-Iterator iter)
       (reverse acc)]
      [else
       (define info (symbol-info (LLVM-Get-Symbol-Name iter)
                                (LLVM-Get-Symbol-Address iter)
                                (LLVM-Get-Symbol-Size iter)))
       (LLVM-Move-To-Next-Symbol iter)
       (loop (cons info acc))])))
