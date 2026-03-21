#lang racket/base

(require ffi/unsafe)

(provide _LLVM-Verifier-Failure-Action
         _LLVM-Code-Gen-Opt-Level
         _LLVM-Code-Model
         _LLVM-Reloc-Mode
         _LLVM-Code-Gen-File-Type
         _LLVM-Int-Predicate
         _LLVM-Linkage
         _LLVM-Visibility
         _LLVM-Real-Predicate)

(define _LLVM-Verifier-Failure-Action
  (_enum '(LLVMAbortProcessAction = 0
           LLVMPrintMessageAction
           LLVMReturnStatusAction)))

(define _LLVM-Code-Gen-Opt-Level
  (_enum '(LLVMCodeGenLevelNone = 0
           LLVMCodeGenLevelLess
           LLVMCodeGenLevelDefault
           LLVMCodeGenLevelAggressive)))

(define _LLVM-Code-Model
  (_enum '(LLVMCodeModelDefault = 0
           LLVMCodeModelJITDefault
           LLVMCodeModelTiny
           LLVMCodeModelSmall
           LLVMCodeModelKernel
           LLVMCodeModelMedium
           LLVMCodeModelLarge)))

(define _LLVM-Reloc-Mode
  (_enum '(LLVMRelocDefault = 0
           LLVMRelocStatic
           LLVMRelocPIC
           LLVMRelocDynamicNoPic
           LLVMRelocROPI
           LLVMRelocRWPI
           LLVMRelocROPI_RWPI)))

(define _LLVM-Code-Gen-File-Type
  (_enum '(LLVMAssemblyFile = 0
           LLVMObjectFile)))

(define _LLVM-Int-Predicate
  (_enum '(LLVMIntEQ = 32
           LLVMIntNE
           LLVMIntUGT
           LLVMIntUGE
           LLVMIntULT
           LLVMIntULE
           LLVMIntSGT
           LLVMIntSGE
           LLVMIntSLT
           LLVMIntSLE)))

(define _LLVM-Real-Predicate
  (_enum '(LLVMRealPredicateFalse = 0
           LLVMRealOEQ
           LLVMRealOGT
           LLVMRealOGE
           LLVMRealOLT
           LLVMRealOLE
           LLVMRealONE
           LLVMRealORD
           LLVMRealUNO
           LLVMRealUEQ
           LLVMRealUGT
           LLVMRealUGE
           LLVMRealULT
           LLVMRealULE
           LLVMRealUNE
           LLVMRealPredicateTrue)))

(define _LLVM-Linkage
  (_enum '(LLVMExternalLinkage = 0
           LLVMAvailableExternallyLinkage
           LLVMLinkOnceAnyLinkage
           LLVMLinkOnceODRLinkage
           LLVMLinkOnceODRAutoHideLinkage
           LLVMWeakAnyLinkage
           LLVMWeakODRLinkage
           LLVMAppendingLinkage
           LLVMInternalLinkage
           LLVMPrivateLinkage
           LLVMDLLImportLinkage
           LLVMDLLExportLinkage
           LLVMExternalWeakLinkage
           LLVMGhostLinkage
           LLVMCommonLinkage
           LLVMLinkerPrivateLinkage
           LLVMLinkerPrivateWeakLinkage)))

(define _LLVM-Visibility
  (_enum '(LLVMDefaultVisibility = 0
           LLVMHiddenVisibility
           LLVMProtectedVisibility)))
