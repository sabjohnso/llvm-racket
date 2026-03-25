#lang racket/base

;; llvm/safe — Safe, high-level LLVM interface for Racket.
;;
;; Provides both a macro layer (define-llvm-module) for direct use
;; and a runtime API (make-llvm-module, call) as a code generator target.

(require "private/safe/syntax.rkt"
         "private/safe/repr.rkt"
         "private/safe/module.rkt")

(provide
 ;; Macro layer
 define-llvm-module

 ;; Runtime API: module construction and execution
 make-llvm-module
 call
 call-fn
 safe-module?
 safe-module-ir

 ;; IR representation: types
 i1 i8 i16 i32 i64 f32 f64 void-type
 ir-type?
 ptr-type ptr-type?
 type-ref type-ref?

 ;; IR representation: record and union declarations
 rec rec?
 field field?
 sum sum?
 variant variant?

 ;; IR representation: expressions
 lit ref
 op icmp fcmp
 app
 if-form
 cond-form cond-clause
 match-variant match-case ctor-pat
 ctor
 rec-new field-ref
 void-expr

 ;; IR representation: functions and bindings
 func formals variable
 body
 named-bindings bind

 ;; IR representation: globals
 define-global)
