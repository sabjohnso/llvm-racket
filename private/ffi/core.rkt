#lang racket/base

;; core.rkt — Re-exports all Core API bindings.
;;
;; The implementation is split into focused modules:
;;   context.rkt   — Context create/dispose
;;   module.rkt    — Module create/dispose, ownership transfer
;;   ir-types.rkt  — Type constructors (integer, float, void, pointer, aggregate)
;;   builder.rkt   — Functions, basic blocks, builder, all instructions
;;   utility.rkt   — Messages, memory buffers

(require "context.rkt"
         "module.rkt"
         "ir-types.rkt"
         "builder.rkt"
         "utility.rkt")

(provide (all-from-out "context.rkt")
         (all-from-out "module.rkt")
         (all-from-out "ir-types.rkt")
         (all-from-out "builder.rkt")
         (all-from-out "utility.rkt"))
