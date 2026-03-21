#lang racket/base

(require ffi/unsafe)

(provide _LLVM-Verifier-Failure-Action
         _LLVM-Code-Gen-Opt-Level
         _LLVM-Code-Model
         _LLVM-Reloc-Mode
         _LLVM-Code-Gen-File-Type)

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
