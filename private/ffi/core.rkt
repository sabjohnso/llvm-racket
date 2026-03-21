#lang racket/base

;; core.rkt — Re-exports all Core API bindings.
;;
;; The implementation is split into focused modules:
;;   context.rkt    — Context create/dispose
;;   module.rkt     — Module create/dispose, ownership transfer
;;   ir-types.rkt   — Type constructors (integer, float, void, pointer, aggregate)
;;   constants.rkt  — Constant values (int, real, null, string, array, struct)
;;   globals.rkt    — Global variables, linkage, visibility, function attributes
;;   builder.rkt    — Functions, basic blocks, builder, all instructions
;;   utility.rkt    — Messages, memory buffers
;;   enums.rkt      — C enumerations (predicates, linkage, visibility, etc.)

(require "context.rkt"
         "module.rkt"
         "ir-types.rkt"
         "constants.rkt"
         "globals.rkt"
         "builder.rkt"
         "utility.rkt"
         "enums.rkt")

(provide (all-from-out "context.rkt")
         (all-from-out "module.rkt")
         (all-from-out "ir-types.rkt")
         (all-from-out "constants.rkt")
         (all-from-out "globals.rkt")
         (all-from-out "builder.rkt")
         (all-from-out "utility.rkt")
         (all-from-out "enums.rkt"))
