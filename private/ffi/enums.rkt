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
         _LLVM-Real-Predicate
         _LLVM-DWARF-Source-Language
         _LLVM-DWARF-Emission-Kind)

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

(define _LLVM-DWARF-Source-Language
  (_enum '(LLVMDWARFSourceLanguageC89 = 0
           LLVMDWARFSourceLanguageC
           LLVMDWARFSourceLanguageAda83
           LLVMDWARFSourceLanguageC_plus_plus
           LLVMDWARFSourceLanguageCobol74
           LLVMDWARFSourceLanguageCobol85
           LLVMDWARFSourceLanguageFortran77
           LLVMDWARFSourceLanguageFortran90
           LLVMDWARFSourceLanguagePascal83
           LLVMDWARFSourceLanguageModula2
           LLVMDWARFSourceLanguageJava
           LLVMDWARFSourceLanguageC99
           LLVMDWARFSourceLanguageAda95
           LLVMDWARFSourceLanguageFortran95
           LLVMDWARFSourceLanguagePLI
           LLVMDWARFSourceLanguageObjC
           LLVMDWARFSourceLanguageObjC_plus_plus
           LLVMDWARFSourceLanguageUPC
           LLVMDWARFSourceLanguageD
           LLVMDWARFSourceLanguagePython
           LLVMDWARFSourceLanguageOpenCL
           LLVMDWARFSourceLanguageGo
           LLVMDWARFSourceLanguageModula3
           LLVMDWARFSourceLanguageHaskell
           LLVMDWARFSourceLanguageC_plus_plus_03
           LLVMDWARFSourceLanguageC_plus_plus_11
           LLVMDWARFSourceLanguageOCaml
           LLVMDWARFSourceLanguageRust
           LLVMDWARFSourceLanguageC11
           LLVMDWARFSourceLanguageSwift)))

(define _LLVM-DWARF-Emission-Kind
  (_enum '(LLVMDWARFEmissionNone = 0
           LLVMDWARFEmissionFull
           LLVMDWARFEmissionLineTablesOnly)))
