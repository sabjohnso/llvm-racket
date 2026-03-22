#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         "lib.rkt")

(provide ;; Parser
         LLVM-Remark-Parser-Create-YAML
         LLVM-Remark-Parser-Dispose
         LLVM-Remark-Parser-Get-Next
         LLVM-Remark-Parser-Has-Error
         LLVM-Remark-Parser-Get-Error-Message
         ;; Entry accessors
         LLVM-Remark-Entry-Dispose
         LLVM-Remark-Entry-Get-Type
         LLVM-Remark-Entry-Get-Pass-Name
         LLVM-Remark-Entry-Get-Remark-Name
         LLVM-Remark-Entry-Get-Function-Name
         ;; String accessors
         LLVM-Remark-String-Get-Data
         LLVM-Remark-String-Get-Len)

;; All remark types are opaque pointers.
(define _LLVM-Remark-Parser-Ref _pointer)
(define _LLVM-Remark-Entry-Ref _pointer)
(define _LLVM-Remark-String-Ref _pointer)

;; ---- Parser ----------------------------------------------------------------

(define LLVMRemarkParserDispose-raw
  (get-ffi-obj "LLVMRemarkParserDispose" llvm-lib
               (_fun _LLVM-Remark-Parser-Ref -> _void)))

(define LLVM-Remark-Parser-Dispose
  ((deallocator) LLVMRemarkParserDispose-raw))

(define register-remark-parser!
  (make-register-allocation LLVM-Remark-Parser-Dispose))

;; LLVMRemarkParserCreateYAML(Buf, Size) -> RemarkParserRef
(define LLVMRemarkParserCreateYAML-raw
  (get-ffi-obj "LLVMRemarkParserCreateYAML" llvm-lib
               (_fun _pointer _uint64 -> _LLVM-Remark-Parser-Ref)))

(define (LLVM-Remark-Parser-Create-YAML buf size)
  (define parser (LLVMRemarkParserCreateYAML-raw buf size))
  (unless parser
    (error 'LLVM-Remark-Parser-Create-YAML "failed to create remark parser"))
  (register-remark-parser! parser)
  parser)

;; Returns the next remark entry, or #f if done.
(define LLVM-Remark-Parser-Get-Next
  (get-ffi-obj "LLVMRemarkParserGetNext" llvm-lib
               (_fun _LLVM-Remark-Parser-Ref -> _pointer)))

(define LLVM-Remark-Parser-Has-Error
  (get-ffi-obj "LLVMRemarkParserHasError" llvm-lib
               (_fun _LLVM-Remark-Parser-Ref -> _bool)))

(define LLVM-Remark-Parser-Get-Error-Message
  (get-ffi-obj "LLVMRemarkParserGetErrorMessage" llvm-lib
               (_fun _LLVM-Remark-Parser-Ref -> _string)))

;; ---- Entry accessors -------------------------------------------------------

(define LLVM-Remark-Entry-Dispose
  (get-ffi-obj "LLVMRemarkEntryDispose" llvm-lib
               (_fun _LLVM-Remark-Entry-Ref -> _void)))

;; Returns an enum value (0=Unknown, 1=Passed, 2=Missed, etc.)
(define LLVM-Remark-Entry-Get-Type
  (get-ffi-obj "LLVMRemarkEntryGetType" llvm-lib
               (_fun _LLVM-Remark-Entry-Ref -> _int)))

(define LLVM-Remark-Entry-Get-Pass-Name
  (get-ffi-obj "LLVMRemarkEntryGetPassName" llvm-lib
               (_fun _LLVM-Remark-Entry-Ref -> _LLVM-Remark-String-Ref)))

(define LLVM-Remark-Entry-Get-Remark-Name
  (get-ffi-obj "LLVMRemarkEntryGetRemarkName" llvm-lib
               (_fun _LLVM-Remark-Entry-Ref -> _LLVM-Remark-String-Ref)))

(define LLVM-Remark-Entry-Get-Function-Name
  (get-ffi-obj "LLVMRemarkEntryGetFunctionName" llvm-lib
               (_fun _LLVM-Remark-Entry-Ref -> _LLVM-Remark-String-Ref)))

;; ---- String accessors ------------------------------------------------------

(define LLVM-Remark-String-Get-Data
  (get-ffi-obj "LLVMRemarkStringGetData" llvm-lib
               (_fun _LLVM-Remark-String-Ref -> _string)))

(define LLVM-Remark-String-Get-Len
  (get-ffi-obj "LLVMRemarkStringGetLen" llvm-lib
               (_fun _LLVM-Remark-String-Ref -> _uint32)))
