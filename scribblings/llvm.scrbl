#lang scribble/manual
@require[@for-label[llvm/unsafe
                    llvm/safe
                    ffi/unsafe
                    racket/base]]

@title{llvm}
@author{sbj}

LLVM bindings for Racket via the LLVM C API.

The package provides two layers:
@itemlist[
  @item{@bold{@tt{llvm/safe}} --- A high-level safe API with Racket-like
        syntax, automatic type checking, optimization, JIT compilation, and
        marshalling.  Start here.}
  @item{@bold{@tt{llvm/unsafe}} --- A thin FFI layer mapping directly to
        the LLVM C API.  Use this when you need full control or access to
        features not yet in the safe API.}
]

@local-table-of-contents[]

@; ===========================================================================
@section{Safe API Guide}

@defmodule[llvm/safe]

The safe API lets you define LLVM modules using Racket-like syntax,
JIT-compile them, and call the resulting native functions.  All type
checking, optimization, and resource management are handled
automatically.

@subsection{Quick Start}

@racketblock[
(require llvm/safe)

(define-llvm-module m
  (define (add [a : Int32] [b : Int32]) (+ a b)))

(call m 'add 3 4) (code:comment "=> 7")
]

@subsection{Defining Functions}

Functions are defined inside @racket[define-llvm-module] using standard
Racket @racket[define] syntax with type-annotated parameters:

@racketblock[
(define-llvm-module m
  (define (square [x : Float64]) (* x x))
  (define (hypotenuse [a : Float64] [b : Float64])
    (let ([a2 : Float64 (* a a)]
          [b2 : Float64 (* b b)])
      (+ a2 b2))))
]

Available primitive types: @racket[Int1] (boolean), @racket[Int8],
@racket[Int16], @racket[Int32], @racket[Int64], @racket[Float32],
@racket[Float64], @racket[Void].

Alternatively, type annotations can be provided separately using
@tt{(: name (-> Arg ... Ret))} notation:

@racketblock[
(define-llvm-module m
  (: add (-> Int32 Int32 Int32))
  (define (add a b) (+ a b)))
]

@subsection{Supported Expressions}

The following expression forms are supported inside function bodies:

@itemlist[
  @item{@bold{Arithmetic}: @racket[+], @racket[-], @racket[*], @racket[/]}
  @item{@bold{Comparisons}: @racket[<], @racket[<=], @racket[>], @racket[>=],
        @racket[=], @racket[!=]}
  @item{@bold{Conditionals}: @racket[if], @racket[cond] (with @racket[else])}
  @item{@bold{Local bindings}: @racket[let] with typed bindings}
  @item{@bold{Loops}: named @racket[let] (compiles to phi nodes + branches)}
  @item{@bold{Function calls}: call other functions defined in the same module}
  @item{@bold{Void}: @racket[(void)] for void-returning functions}
  @item{@bold{Integer and float literals}: @racket[42], @racket[3.14]}
]

Arithmetic and comparison operators are type-overloaded: @racket[+] on
@racket[Int32] emits integer add, on @racket[Float64] emits float add.

@subsection{Conditionals and Loops}

@racketblock[
(code:comment "if expression")
(if (> a b) a b)

(code:comment "cond expression (must have else)")
(cond
  [(< x 0)  -1]
  [(= x 0)   0]
  [else       1])

(code:comment "named let (loop)")
(let loop ([i : Int32 n] [acc : Int32 1])
  (if (<= i 1) acc (loop (- i 1) (* acc i))))
]

@subsection{Defining Record Types}

Define record (struct) types with @racket[define-record]:

@racketblock[
(define-llvm-module m
  (define-record Point ([x : Float64] [y : Float64]))

  (define (distance-sq [ax : Float64] [ay : Float64]
                       [bx : Float64] [by : Float64])
    (let ([dx : Float64 (- (Point-x (Point ax ay))
                            (Point-x (Point bx by)))]
          [dy : Float64 (- (Point-y (Point ax ay))
                            (Point-y (Point bx by)))])
      (+ (* dx dx) (* dy dy)))))
]

Record constructors use the type name: @racket[(Point x y)].
Field accessors use @tt{TypeName-fieldName}: @racket[(Point-x p)].

@subsection{Tagged Unions}

Define tagged union types with @racket[union] and pattern match with
@racket[match]:

@racketblock[
(define-llvm-module m
  (union Opt-Int
    [Some ([value : Int32])]
    [None])

  (define (unwrap [x : Int32])
    (match (Some x)
      [(Some v) v]
      [(None)   0])))
]

Variant constructors: @racket[(Some 42)], @racket[(None)].

@subsection{Passing Records and Unions to @tt{call}}

Records are passed as Racket lists matching field order.  Unions are
passed as tagged lists:

@racketblock[
(call m 'get-x '(3.0 4.0))       (code:comment "Pass a Point record")
(call m 'unwrap '(Some 42))       (code:comment "Pass a Some variant")
(call m 'unwrap '(None))          (code:comment "Pass a None variant")
]

@subsection{Configuring Optimization}

By default, @racket[make-llvm-module] runs LLVM's @tt{default<O2>}
optimization pipeline.  You can customize this:

@racketblock[
(code:comment "Aggressive optimization")
(make-llvm-module #:optimize "default<O3>" ...)

(code:comment "Disable optimization")
(make-llvm-module #:optimize #f ...)
]

@subsection{Using the Runtime API}

The runtime API is the code generator target.  It builds an IR
representation as pure data, then compiles it:

@racketblock[
(require llvm/safe)

(define m
  (make-llvm-module
   (func 'add (formals (variable 'a i32) (variable 'b i32))
         (body ((op '+) (ref 'a) (ref 'b))))))

(call m 'add 3 4) (code:comment "=> 7")
]

The runtime API constructors (@racket[func], @racket[formals],
@racket[variable], @racket[body], @racket[op], @racket[ref],
@racket[lit], etc.) build a data representation that is validated
and compiled by @racket[make-llvm-module].  No LLVM interaction
occurs until @racket[make-llvm-module] is called.

@; ===========================================================================
@section{Safe API Reference}

@subsection{Module Construction and Execution}

@defform[(define-llvm-module name body ...)]{
Define an LLVM module using Racket-like syntax.  @racket[body] forms
can be function definitions, record definitions, union definitions,
and type annotations.  The module is compiled, optimized, and
JIT-compiled automatically.  Binds @racket[name] to a @racket[safe-module?].}

@defproc[(make-llvm-module [#:optimize optimize (or/c string? #f) "default<O2>"]
                           [decl any/c] ...)
         safe-module?]{
Compile a list of IR declarations into a JIT-compiled module.  Each
@racket[decl] is a @racket[func], @racket[rec], @racket[sum], or
@racket[define-global] form.  Pass @racket[#:optimize #f] to disable
optimization, or a pipeline string like @racket["default<O3>"].}

@defproc[(call [m safe-module?] [fn-name symbol?] [arg any/c] ...) any/c]{
Call a JIT-compiled function by name.  Arguments are automatically
marshalled: primitives pass through, records as lists, unions as
tagged lists.  Returns the function's result, or @racket[(void)] for
void functions.}

@defproc[(safe-module? [v any/c]) boolean?]{
Predicate for compiled safe modules.}

@defproc[(safe-module-ir [m safe-module?]) string?]{
Return the LLVM IR text of a compiled module (useful for debugging).}

@subsection{Primitive Types}

@deftogether[(@defthing[i1 ir-type?]
              @defthing[i8 ir-type?]
              @defthing[i16 ir-type?]
              @defthing[i32 ir-type?]
              @defthing[i64 ir-type?])]{
Integer types of 1, 8, 16, 32, and 64 bits.}

@deftogether[(@defthing[f32 ir-type?]
              @defthing[f64 ir-type?])]{
32-bit and 64-bit IEEE floating point types.}

@defthing[void-type ir-type?]{The void type (for functions that return nothing).}

@subsection{Functions and Bindings}

@defproc[(func [name symbol?] [formals formals?] [body body?]) func?]{
Declare a function with @racket[name], formal parameters, and a body.}

@defproc[(formals [var variable?] ...) formals?]{
Declare formal parameters for a function.}

@defproc[(variable [name symbol?] [type ir-type?]) variable?]{
Declare a typed variable.}

@defproc[(body [expr any/c] ...) body?]{
A sequence of expressions.  The last expression's value is returned
(like @racket[begin]).}

@defproc[(named-bindings [name symbol?] [binds (listof bind?)] [body body?])
         named-bindings?]{
A named let / loop.  @racket[binds] are the initial bindings,
@racket[body] is the loop body.  Recurrence is via @racket[app] to
@racket[name].}

@defproc[(bind [var variable?] [init any/c]) bind?]{
A binding: variable + initial value expression.}

@subsection{Expressions}

@defproc[(lit [value any/c] [type ir-type?]) lit?]{
A literal constant.}

@defproc[(ref [name symbol?]) ref?]{
A reference to a variable or parameter by name.}

@defproc[(op [sym symbol?]) procedure?]{
Returns a function that constructs an operator application.
Operators: @racket['+], @racket['-], @racket['*], @racket['/],
@racket['neg], @racket['bit-and], @racket['bit-or], @racket['bit-xor],
@racket['bit-not], @racket['shl], @racket['shr].}

@defproc[(icmp [pred symbol?]) procedure?]{
Returns a function that constructs an integer comparison.
Predicates: @racket['=], @racket['!=], @racket['<], @racket['<=],
@racket['>], @racket['>=].}

@defproc[(fcmp [pred symbol?]) procedure?]{
Returns a function that constructs a float comparison.  Same
predicates as @racket[icmp].}

@defproc[(app [callee ref?] [arg any/c] ...) app?]{
Function or loop application.}

@defproc[(if-form [condition any/c] [then any/c] [else any/c]) if-form?]{
Conditional expression.  @racket[condition] must be @racket[i1].
Both branches must have the same type.}

@defproc[(cond-form [clauses (listof cond-clause?)] [else any/c]) cond-form?]{
Multi-way conditional.}

@defproc[(cond-clause [test any/c] [expr any/c]) cond-clause?]{
A clause for @racket[cond-form].}

@defproc[(void-expr) void-expr?]{
Void expression, used as the last expression in a void-returning function.}

@subsection{Record Types}

@defproc[(rec [name symbol?] [fld field?] ...) rec?]{
Declare a record (struct) type.}

@defproc[(field [name symbol?] [type ir-type?]) field?]{
Declare a field in a record or variant.}

@defproc[(rec-new [type-name symbol?] [arg any/c] ...) rec-new?]{
Construct a record value.}

@defproc[(field-ref [expr any/c] [type-name symbol?] [field-name symbol?])
         field-ref?]{
Access a field from a record.}

@subsection{Tagged Union Types}

@defproc[(sum [name symbol?] [var variant?] ...) sum?]{
Declare a tagged union type.}

@defproc[(variant [name symbol?] [fld field?] ...) variant?]{
Declare a variant of a tagged union.  Variants with no fields are
allowed: @racket[(variant 'None)].}

@defproc[(ctor [variant-name symbol?] [arg any/c] ...) ctor?]{
Construct a tagged union value.}

@defproc[(match-variant [scrutinee any/c] [case match-case?] ...) match-variant?]{
Pattern match on a tagged union.}

@defproc[(match-case [pat ctor-pat?] [body body?]) match-case?]{
A case in a @racket[match-variant].}

@defproc[(ctor-pat [variant-name symbol?] [binding variable?] ...) ctor-pat?]{
A pattern that matches a variant and binds its fields.}

@subsection{Type References and Pointers}

@defproc[(type-ref [name symbol?]) type-ref?]{
Reference a user-defined type (record or union) by name.}

@defproc[(ptr-type [element ir-type?]) ptr-type?]{
A pointer type.}

@; ===========================================================================
@section{Unsafe FFI Guide}

@; ---------------------------------------------------------------------------
@subsection{Quick Start: ORC JIT}

Build an @tt{add(i32, i32) -> i32} function, JIT-compile it with the
modern ORC JIT, and call it:

@racketblock[
(require llvm/unsafe ffi/unsafe)

(Initialize-Native-Target!)

(code:comment "Create a thread-safe context and build IR")
(define ts-ctx (LLVM-Orc-Create-New-Thread-Safe-Context))
(define ctx (LLVM-Orc-Thread-Safe-Context-Get-Context ts-ctx))
(define mod (LLVM-Module-Create-With-Name-In-Context "example" ctx))
(define i32 (LLVM-Int32-Type-In-Context ctx))
(define fn (LLVM-Add-Function mod "add"
             (LLVM-Function-Type i32 (list i32 i32) 2 0)))
(define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
(define bld (LLVM-Create-Builder-In-Context ctx))
(LLVM-Position-Builder-At-End bld bb)
(LLVM-Build-Ret bld
  (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                      (LLVM-Get-Param fn 1) "tmp"))

(code:comment "Verify and wrap in a thread-safe module")
(LLVM-Verify-Module mod 'LLVMReturnStatusAction)
(define ts-mod (LLVM-Orc-Create-New-Thread-Safe-Module mod ts-ctx))

(code:comment "Create LLJIT and add the module")
(define jit (LLVM-Orc-Create-LLJIT #f))
(LLVM-Orc-LLJIT-Add-LLVM-IR-Module
 jit (LLVM-Orc-LLJIT-Get-Main-JIT-Dylib jit) ts-mod)

(code:comment "Look up and call the function")
(define add-fn
  (cast (LLVM-Orc-LLJIT-Lookup jit "add")
        _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4) (code:comment "=> 7")
]

@; ---------------------------------------------------------------------------
@subsection{Quick Start: MCJIT (Legacy)}

MCJIT is the older JIT engine.  It compiles an entire module at once and
does not support incremental compilation.  Prefer ORC JIT for new code.

@racketblock[
(require llvm/unsafe ffi/unsafe)

(Initialize-Native-Target!)
(LLVM-Link-In-MCJIT)

(code:comment "Build the IR")
(define ctx (LLVM-Context-Create))
(define mod (LLVM-Module-Create-With-Name-In-Context "example" ctx))
(define i32 (LLVM-Int32-Type-In-Context ctx))
(define fn (LLVM-Add-Function mod "add"
             (LLVM-Function-Type i32 (list i32 i32) 2 0)))
(define bb (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
(define bld (LLVM-Create-Builder-In-Context ctx))
(LLVM-Position-Builder-At-End bld bb)
(LLVM-Build-Ret bld
  (LLVM-Build-Add bld (LLVM-Get-Param fn 0)
                      (LLVM-Get-Param fn 1) "tmp"))

(code:comment "Verify and JIT compile")
(LLVM-Verify-Module mod 'LLVMReturnStatusAction)
(define opts
  (make-LLVM-MCJIT-Compiler-Options
   0 'LLVMCodeModelJITDefault 0 0 #f))
(LLVM-Initialize-MCJIT-Compiler-Options
 opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
(define ee
  (LLVM-Create-MCJIT-Compiler-For-Module
   mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))

(code:comment "Call the JIT'd function")
(define add-fn
  (cast (LLVM-Get-Function-Address ee "add")
        _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4) (code:comment "=> 7")
]

@; ---------------------------------------------------------------------------
@subsection{Building IR}

LLVM IR is built by creating a context, a module, functions with basic
blocks, and using a builder to emit instructions:

@itemlist[
  @item{@bold{Context} --- owns types, metadata, and string tables.
        Create with @racket[LLVM-Context-Create].  For ORC JIT, use
        @racket[LLVM-Orc-Create-New-Thread-Safe-Context] instead.}
  @item{@bold{Module} --- a container for functions and globals.
        Create with @racket[LLVM-Module-Create-With-Name-In-Context].}
  @item{@bold{Function} --- declared with @racket[LLVM-Add-Function]
        and a function type from @racket[LLVM-Function-Type].}
  @item{@bold{Basic block} --- an instruction sequence with a single
        entry and terminator.  Append with
        @racket[LLVM-Append-Basic-Block-In-Context].}
  @item{@bold{Builder} --- a cursor that emits instructions into a
        basic block.  Position with @racket[LLVM-Position-Builder-At-End],
        then call @racket[LLVM-Build-Add], @racket[LLVM-Build-Ret], etc.}
]

Every basic block must end with a terminator (@racket[LLVM-Build-Ret],
@racket[LLVM-Build-Br], @racket[LLVM-Build-Cond-Br], or
@racket[LLVM-Build-Unreachable]).

@; ---------------------------------------------------------------------------
@subsection{Optimization}

Use the new pass manager to optimize a module:

@racketblock[
(define opts (LLVM-Create-Pass-Builder-Options))
(LLVM-Run-Passes mod "default<O2>" tm opts)
]

Common pipeline strings: @racket["default<O0>"] through @racket["default<O3>"],
or individual passes like @racket["mem2reg,instcombine,gvn"].

The legacy pass manager is also available for per-function optimization.

@; ---------------------------------------------------------------------------
@subsection{Serialization}

Modules can be serialized to bitcode and loaded back:

@racketblock[
(code:comment "Save")
(LLVM-Write-Bitcode-To-File mod "output.bc")

(code:comment "Load")
(define mod2 (LLVM-Parse-Bitcode-File ctx "output.bc"))
]

LLVM IR text (@tt{.ll} files) can be parsed with
@racket[LLVM-Parse-IR-In-Context], and the IR text of any module can be
retrieved with @racket[LLVM-Print-Module-To-String].

@; ---------------------------------------------------------------------------
@subsection{Resource Management}

All LLVM resources allocated through this library are tracked by the
garbage collector.  When a resource becomes unreachable, its finalizer
runs automatically.  You @bold{do not} need to call @tt{Dispose} functions
manually --- the GC handles cleanup.

Lifetime dependencies are also tracked: a module keeps its context alive,
a function keeps its module alive, and so on.  You cannot accidentally
cause a use-after-free by dropping a parent reference while a child is
still reachable.

When a module is passed to @racket[LLVM-Create-MCJIT-Compiler-For-Module]
or @racket[LLVM-Orc-Create-New-Thread-Safe-Module], its ownership
transfers.  The module's finalizer is canceled and the new owner takes
responsibility for freeing it.

@bold{Context isolation.}  Every type, module, builder, and function
belongs to exactly one context.  Do not mix objects from different
contexts --- for example, do not use a type created in one context to
define a function in a module from another context.  LLVM will not
detect the mismatch; the result is silent corruption or a crash.
When in doubt, create a single context and use it everywhere.

@; ===========================================================================
@section{Unsafe FFI Reference}

@defmodule[llvm/unsafe]

The thin FFI layer maps directly to the
@hyperlink["https://llvm.org/doxygen/group__LLVMC.html"]{LLVM C API}.
Naming follows uppercase-kebab convention: the C function
@tt{LLVMContextCreate} becomes @racket[LLVM-Context-Create].
All resources are GC-managed.  Errors are raised as @racket[exn:fail].

@; ---------------------------------------------------------------------------
@subsection{Library Loading}

@defproc[(llvm-lib) ffi-lib?]{
The loaded @tt{libLLVM} shared library handle.

Library search order:
@itemlist[
  @item{@envvar{LLVM_LIB_PATH} environment variable (explicit path)}
  @item{Default system library search (@tt{libLLVM.so.20} through @tt{.15})}
  @item{Well-known directories: @tt{/usr/lib/llvm-@italic{N}/lib},
        @tt{/usr/lib}, @tt{/usr/lib64}, @tt{/usr/local/lib}}
]}

@; ---------------------------------------------------------------------------
@subsection{Opaque Pointer Types}

Each LLVM handle is represented as an opaque @racket[cpointer] type.
For every type @racket[_LLVM-@italic{Foo}-Ref] there is a corresponding
@racket[_LLVM-@italic{Foo}-Ref/null] variant that accepts @racket[#f]
for null pointers.

@deftogether[(@defthing[_LLVM-Context-Ref ctype?]
              @defthing[_LLVM-Context-Ref/null ctype?])]{
An LLVM context handle.}

@deftogether[(@defthing[_LLVM-Module-Ref ctype?]
              @defthing[_LLVM-Module-Ref/null ctype?])]{
An LLVM module handle.}

@deftogether[(@defthing[_LLVM-Type-Ref ctype?]
              @defthing[_LLVM-Type-Ref/null ctype?])]{
An LLVM type handle.}

@deftogether[(@defthing[_LLVM-Value-Ref ctype?]
              @defthing[_LLVM-Value-Ref/null ctype?])]{
An LLVM value handle (functions, instructions, constants, etc.).}

@deftogether[(@defthing[_LLVM-Basic-Block-Ref ctype?]
              @defthing[_LLVM-Basic-Block-Ref/null ctype?])]{
An LLVM basic block handle.}

@deftogether[(@defthing[_LLVM-Builder-Ref ctype?]
              @defthing[_LLVM-Builder-Ref/null ctype?])]{
An LLVM IR builder handle.}

@deftogether[(@defthing[_LLVM-Execution-Engine-Ref ctype?]
              @defthing[_LLVM-Execution-Engine-Ref/null ctype?])]{
An LLVM execution engine (JIT) handle.}

@deftogether[(@defthing[_LLVM-Generic-Value-Ref ctype?]
              @defthing[_LLVM-Generic-Value-Ref/null ctype?])]{
A boxed value for passing arguments to JIT'd functions via @racket[LLVM-Run-Function].}

@deftogether[(@defthing[_LLVM-Pass-Manager-Ref ctype?]
              @defthing[_LLVM-Pass-Manager-Ref/null ctype?])]{
An LLVM pass manager handle.}

@deftogether[(@defthing[_LLVM-Memory-Buffer-Ref ctype?]
              @defthing[_LLVM-Memory-Buffer-Ref/null ctype?])]{
An LLVM memory buffer handle.}

@deftogether[(@defthing[_LLVM-MCJIT-Memory-Manager-Ref ctype?]
              @defthing[_LLVM-MCJIT-Memory-Manager-Ref/null ctype?])]{
An MCJIT custom memory manager handle.}

@deftogether[(@defthing[_LLVM-Target-Ref ctype?]
              @defthing[_LLVM-Target-Ref/null ctype?])]{
An LLVM target description handle.}

@deftogether[(@defthing[_LLVM-Target-Machine-Ref ctype?]
              @defthing[_LLVM-Target-Machine-Ref/null ctype?])]{
An LLVM target machine handle.}

@deftogether[(@defthing[_LLVM-Pass-Builder-Options-Ref ctype?]
              @defthing[_LLVM-Pass-Builder-Options-Ref/null ctype?])]{
Pass builder options handle (for the new pass manager).}

@deftogether[(@defthing[_LLVM-Orc-LLJIT-Ref ctype?]
              @defthing[_LLVM-Orc-LLJIT-Ref/null ctype?])]{
An ORC LLJIT (JIT compiler) handle.}

@deftogether[(@defthing[_LLVM-Orc-JIT-Dylib-Ref ctype?]
              @defthing[_LLVM-Orc-JIT-Dylib-Ref/null ctype?])]{
An ORC JIT dynamic library handle.}

@deftogether[(@defthing[_LLVM-Orc-Thread-Safe-Context-Ref ctype?]
              @defthing[_LLVM-Orc-Thread-Safe-Context-Ref/null ctype?])]{
An ORC thread-safe context handle.}

@deftogether[(@defthing[_LLVM-Orc-Thread-Safe-Module-Ref ctype?]
              @defthing[_LLVM-Orc-Thread-Safe-Module-Ref/null ctype?])]{
An ORC thread-safe module handle.}

@deftogether[(@defthing[_LLVM-Orc-Execution-Session-Ref ctype?]
              @defthing[_LLVM-Orc-Execution-Session-Ref/null ctype?])]{
An ORC execution session handle.}

@deftogether[(@defthing[_LLVM-Object-File-Ref ctype?]
              @defthing[_LLVM-Object-File-Ref/null ctype?])]{
An object file handle.}

@deftogether[(@defthing[_LLVM-Section-Iterator-Ref ctype?]
              @defthing[_LLVM-Section-Iterator-Ref/null ctype?])]{
An object file section iterator handle.}

@deftogether[(@defthing[_LLVM-Symbol-Iterator-Ref ctype?]
              @defthing[_LLVM-Symbol-Iterator-Ref/null ctype?])]{
An object file symbol iterator handle.}

@deftogether[(@defthing[_LLVM-Relocation-Iterator-Ref ctype?]
              @defthing[_LLVM-Relocation-Iterator-Ref/null ctype?])]{
An object file relocation iterator handle.}

@deftogether[(@defthing[_LLVM-DI-Builder-Ref ctype?]
              @defthing[_LLVM-DI-Builder-Ref/null ctype?])]{
A debug info builder handle.}

@deftogether[(@defthing[_LLVM-Metadata-Ref ctype?]
              @defthing[_LLVM-Metadata-Ref/null ctype?])]{
An LLVM metadata handle (debug info nodes, etc.).}

@defthing[_LLVM-Bool ctype?]{
Integer type used as a boolean in the LLVM C API (@racket[_int]).
Zero is false; non-zero is true.}

@; ---------------------------------------------------------------------------
@subsection{Enumerations}

Enumerations are defined as Racket @racket[_enum] types. Pass enum values
as quoted symbols (e.g., @racket['LLVMReturnStatusAction]).

@defthing[_LLVM-Verifier-Failure-Action ctype?]{
Action to take when module verification fails.

@itemlist[
  @item{@racket['LLVMAbortProcessAction] (0) --- abort the process}
  @item{@racket['LLVMPrintMessageAction] (1) --- print to stderr}
  @item{@racket['LLVMReturnStatusAction] (2) --- return a status code}
]}

@defthing[_LLVM-Code-Gen-Opt-Level ctype?]{
Code generation optimization level.

@itemlist[
  @item{@racket['LLVMCodeGenLevelNone] (0)}
  @item{@racket['LLVMCodeGenLevelLess] (1)}
  @item{@racket['LLVMCodeGenLevelDefault] (2)}
  @item{@racket['LLVMCodeGenLevelAggressive] (3)}
]}

@defthing[_LLVM-Code-Model ctype?]{
Code model for code generation.

@itemlist[
  @item{@racket['LLVMCodeModelDefault] (0)}
  @item{@racket['LLVMCodeModelJITDefault] (1)}
  @item{@racket['LLVMCodeModelTiny] (2)}
  @item{@racket['LLVMCodeModelSmall] (3)}
  @item{@racket['LLVMCodeModelKernel] (4)}
  @item{@racket['LLVMCodeModelMedium] (5)}
  @item{@racket['LLVMCodeModelLarge] (6)}
]}

@defthing[_LLVM-Reloc-Mode ctype?]{
Relocation model.

@itemlist[
  @item{@racket['LLVMRelocDefault] (0)}
  @item{@racket['LLVMRelocStatic] (1)}
  @item{@racket['LLVMRelocPIC] (2)}
  @item{@racket['LLVMRelocDynamicNoPic] (3)}
  @item{@racket['LLVMRelocROPI] (4)}
  @item{@racket['LLVMRelocRWPI] (5)}
  @item{@racket['LLVMRelocROPI_RWPI] (6)}
]}

@defthing[_LLVM-Code-Gen-File-Type ctype?]{
Output file type for code generation.

@itemlist[
  @item{@racket['LLVMAssemblyFile] (0)}
  @item{@racket['LLVMObjectFile] (1)}
]}

@defthing[_LLVM-Int-Predicate ctype?]{
Integer comparison predicate for @racket[LLVM-Build-ICmp].

@itemlist[
  @item{@racket['LLVMIntEQ] (32) --- equal}
  @item{@racket['LLVMIntNE] (33) --- not equal}
  @item{@racket['LLVMIntUGT] (34) --- unsigned greater than}
  @item{@racket['LLVMIntUGE] (35) --- unsigned greater or equal}
  @item{@racket['LLVMIntULT] (36) --- unsigned less than}
  @item{@racket['LLVMIntULE] (37) --- unsigned less or equal}
  @item{@racket['LLVMIntSGT] (38) --- signed greater than}
  @item{@racket['LLVMIntSGE] (39) --- signed greater or equal}
  @item{@racket['LLVMIntSLT] (40) --- signed less than}
  @item{@racket['LLVMIntSLE] (41) --- signed less or equal}
]}

@defthing[_LLVM-Real-Predicate ctype?]{
Floating point comparison predicate for @racket[LLVM-Build-FCmp].

@itemlist[
  @item{@racket['LLVMRealPredicateFalse] (0) --- always false}
  @item{@racket['LLVMRealOEQ] (1) --- ordered and equal}
  @item{@racket['LLVMRealOGT] (2) --- ordered and greater than}
  @item{@racket['LLVMRealOGE] (3) --- ordered and greater or equal}
  @item{@racket['LLVMRealOLT] (4) --- ordered and less than}
  @item{@racket['LLVMRealOLE] (5) --- ordered and less or equal}
  @item{@racket['LLVMRealONE] (6) --- ordered and not equal}
  @item{@racket['LLVMRealORD] (7) --- ordered (no NaNs)}
  @item{@racket['LLVMRealUNO] (8) --- unordered (either is NaN)}
  @item{@racket['LLVMRealUEQ] (9) --- unordered or equal}
  @item{@racket['LLVMRealUGT] (10) --- unordered or greater than}
  @item{@racket['LLVMRealUGE] (11) --- unordered or greater or equal}
  @item{@racket['LLVMRealULT] (12) --- unordered or less than}
  @item{@racket['LLVMRealULE] (13) --- unordered or less or equal}
  @item{@racket['LLVMRealUNE] (14) --- unordered or not equal}
  @item{@racket['LLVMRealPredicateTrue] (15) --- always true}
]}

@defthing[_LLVM-Linkage ctype?]{
Linkage type for global values.  Common values:
@itemlist[
  @item{@racket['LLVMExternalLinkage] (0) --- externally visible (default)}
  @item{@racket['LLVMInternalLinkage] (8) --- internal (like C @tt{static})}
  @item{@racket['LLVMPrivateLinkage] (9) --- like internal, omitted from symbol table}
  @item{@racket['LLVMWeakAnyLinkage] (5) --- weak linkage}
  @item{@racket['LLVMCommonLinkage] (14) --- tentative definitions}
]}

@defthing[_LLVM-Visibility ctype?]{
Visibility for global values.
@itemlist[
  @item{@racket['LLVMDefaultVisibility] (0)}
  @item{@racket['LLVMHiddenVisibility] (1)}
  @item{@racket['LLVMProtectedVisibility] (2)}
]}

@defthing[_LLVM-DWARF-Source-Language ctype?]{
DWARF source language for debug info compile units.  Common values:
@itemlist[
  @item{@racket['LLVMDWARFSourceLanguageC] (1) --- C}
  @item{@racket['LLVMDWARFSourceLanguageC99] (11) --- C99}
  @item{@racket['LLVMDWARFSourceLanguageC11] (28) --- C11}
  @item{@racket['LLVMDWARFSourceLanguageC_plus_plus] (3) --- C++}
  @item{@racket['LLVMDWARFSourceLanguageRust] (27) --- Rust}
  @item{@racket['LLVMDWARFSourceLanguagePython] (19) --- Python}
]}

@defthing[_LLVM-DWARF-Emission-Kind ctype?]{
DWARF debug info emission level.
@itemlist[
  @item{@racket['LLVMDWARFEmissionNone] (0) --- no debug info}
  @item{@racket['LLVMDWARFEmissionFull] (1) --- full debug info}
  @item{@racket['LLVMDWARFEmissionLineTablesOnly] (2) --- line tables only}
]}

@; ---------------------------------------------------------------------------
@subsection{Core --- Contexts}

@defproc[(LLVM-Context-Create) _LLVM-Context-Ref]{
Create a new LLVM context. Every context must eventually be freed with
@racket[LLVM-Context-Dispose].}

@defproc[(LLVM-Context-Dispose [ctx _LLVM-Context-Ref]) void?]{
Dispose of a context and all entities owned by it.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Modules}

@defproc[(LLVM-Module-Create-With-Name-In-Context
           [name string?]
           [ctx _LLVM-Context-Ref])
         _LLVM-Module-Ref]{
Create a new module with the given @racket[name] in @racket[ctx].}

@defproc[(LLVM-Dispose-Module [mod _LLVM-Module-Ref]) void?]{
Dispose of a module. Do @bold{not} call this if the module has been passed
to @racket[LLVM-Create-MCJIT-Compiler-For-Module] --- the execution engine
takes ownership.}

@defproc[(LLVM-Print-Module-To-String [mod _LLVM-Module-Ref]) cpointer?]{
Return the module's LLVM IR as a C string pointer. The caller must free the
result with @racket[LLVM-Dispose-Message].}

@defproc[(LLVM-Dispose-Message [msg cpointer?]) void?]{
Free a string allocated by LLVM (e.g., from @racket[LLVM-Print-Module-To-String]
or error out-parameters).}

@; ---------------------------------------------------------------------------
@subsection{Core --- Types}

All type constructors return handles into the context.  The context is
kept alive as long as any type ref derived from it is reachable.

@subsubsection{Integer Types}

@defproc[(LLVM-Int1-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{i1} (boolean) type.}

@defproc[(LLVM-Int8-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{i8} type.}

@defproc[(LLVM-Int16-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{i16} type.}

@defproc[(LLVM-Int32-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{i32} type.}

@defproc[(LLVM-Int64-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{i64} type.}

@defproc[(LLVM-Int-Type-In-Context
           [ctx _LLVM-Context-Ref]
           [num-bits exact-nonnegative-integer?])
         _LLVM-Type-Ref]{
Return an integer type with @racket[num-bits] width (e.g., 128 for @tt{i128}).}

@subsubsection{Floating Point Types}

@defproc[(LLVM-Float-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the 32-bit IEEE @tt{float} type.}

@defproc[(LLVM-Double-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the 64-bit IEEE @tt{double} type.}

@subsubsection{Void and Pointer Types}

@defproc[(LLVM-Void-Type-In-Context [ctx _LLVM-Context-Ref]) _LLVM-Type-Ref]{
Return the @tt{void} type (used as function return type for procedures
that return nothing).}

@defproc[(LLVM-Pointer-Type-In-Context
           [ctx _LLVM-Context-Ref]
           [address-space exact-nonnegative-integer?])
         _LLVM-Type-Ref]{
Return an opaque pointer type (@tt{ptr}) in the given address space.
Pass @racket[0] for the default address space.}

@subsubsection{Aggregate Types}

@defproc[(LLVM-Struct-Type-In-Context
           [ctx _LLVM-Context-Ref]
           [element-types (listof _LLVM-Type-Ref)]
           [element-count exact-nonnegative-integer?]
           [packed _LLVM-Bool])
         _LLVM-Type-Ref]{
Create an anonymous struct type.  Pass @racket[0] for @racket[packed]
for normal alignment.}

@defproc[(LLVM-Struct-Create-Named
           [ctx _LLVM-Context-Ref]
           [name string?])
         _LLVM-Type-Ref]{
Create a named (opaque) struct type.  Set its body with
@racket[LLVM-Struct-Set-Body].}

@defproc[(LLVM-Struct-Set-Body
           [struct-type _LLVM-Type-Ref]
           [element-types (listof _LLVM-Type-Ref)]
           [element-count exact-nonnegative-integer?]
           [packed _LLVM-Bool])
         void?]{
Set the body of a named struct type created with
@racket[LLVM-Struct-Create-Named].}

@defproc[(LLVM-Array-Type
           [element-type _LLVM-Type-Ref]
           [count exact-nonnegative-integer?])
         _LLVM-Type-Ref]{
Create an array type of @racket[count] elements of @racket[element-type].}

@defproc[(LLVM-Vector-Type
           [element-type _LLVM-Type-Ref]
           [count exact-nonnegative-integer?])
         _LLVM-Type-Ref]{
Create a fixed-length SIMD vector type of @racket[count] elements.}

@subsubsection{Function Types}

@defproc[(LLVM-Function-Type
           [return-type _LLVM-Type-Ref]
           [param-types (listof _LLVM-Type-Ref)]
           [param-count exact-nonnegative-integer?]
           [is-vararg _LLVM-Bool])
         _LLVM-Type-Ref]{
Create a function type. @racket[param-count] must equal
@racket[(length param-types)]. Pass @racket[0] for @racket[is-vararg]
for non-variadic functions.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Constants}

@defproc[(LLVM-Const-Int [type _LLVM-Type-Ref] [val exact-nonnegative-integer?] [sign-extend _LLVM-Bool]) _LLVM-Value-Ref]{
Create an integer constant.  Pass @racket[0] for @racket[sign-extend] for unsigned.}

@defproc[(LLVM-Const-Real [type _LLVM-Type-Ref] [val real?]) _LLVM-Value-Ref]{
Create a floating point constant.}

@defproc[(LLVM-Const-Null [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Create a null/zero constant of the given type.}

@defproc[(LLVM-Const-All-Ones [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Create an all-ones constant (e.g., @tt{-1} for integers).}

@defproc[(LLVM-Get-Undef [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Create an undefined value of the given type.}

@defproc[(LLVM-Const-String-In-Context [ctx _LLVM-Context-Ref] [str string?] [length exact-nonnegative-integer?] [dont-null-terminate _LLVM-Bool]) _LLVM-Value-Ref]{
Create a constant string.  Pass @racket[0] for @racket[dont-null-terminate]
to append a null byte.}

@defproc[(LLVM-Const-Array [element-type _LLVM-Type-Ref] [values (listof _LLVM-Value-Ref)] [count exact-nonnegative-integer?]) _LLVM-Value-Ref]{
Create a constant array.}

@defproc[(LLVM-Const-Struct [values (listof _LLVM-Value-Ref)] [count exact-nonnegative-integer?] [packed _LLVM-Bool]) _LLVM-Value-Ref]{
Create an anonymous constant struct.}

@defproc[(LLVM-Const-Named-Struct [type _LLVM-Type-Ref] [values (listof _LLVM-Value-Ref)] [count exact-nonnegative-integer?]) _LLVM-Value-Ref]{
Create a constant of a named struct type.}

@defproc[(LLVM-Const-GEP2 [type _LLVM-Type-Ref] [val _LLVM-Value-Ref] [indices (listof _LLVM-Value-Ref)] [num-indices exact-nonnegative-integer?]) _LLVM-Value-Ref]{
Constant get-element-pointer expression.}

@defproc[(LLVM-Const-Bit-Cast [val _LLVM-Value-Ref] [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Constant bitcast expression.}

@defproc[(LLVM-Const-Int-To-Ptr [val _LLVM-Value-Ref] [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Constant integer-to-pointer expression.}

@defproc[(LLVM-Const-Ptr-To-Int [val _LLVM-Value-Ref] [type _LLVM-Type-Ref]) _LLVM-Value-Ref]{
Constant pointer-to-integer expression.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Global Variables}

@defproc[(LLVM-Add-Global [mod _LLVM-Module-Ref] [type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{
Add a global variable to @racket[mod].}

@defproc[(LLVM-Set-Initializer [global _LLVM-Value-Ref] [val _LLVM-Value-Ref]) void?]{
Set the initializer for a global variable.}

@defproc[(LLVM-Get-Initializer [global _LLVM-Value-Ref]) (or/c _LLVM-Value-Ref #f)]{
Get the initializer of a global variable, or @racket[#f] if none.}

@defproc[(LLVM-Set-Global-Constant [global _LLVM-Value-Ref] [is-constant _LLVM-Bool]) void?]{
Mark a global variable as constant.}

@defproc[(LLVM-Set-Alignment [val _LLVM-Value-Ref] [bytes exact-nonnegative-integer?]) void?]{
Set the alignment of a global variable or alloca.}

@defproc[(LLVM-Set-Linkage [global _LLVM-Value-Ref] [linkage _LLVM-Linkage]) void?]{
Set the linkage type of a global value (function or global variable).}

@defproc[(LLVM-Get-Linkage [global _LLVM-Value-Ref]) _LLVM-Linkage]{
Get the linkage type of a global value.}

@defproc[(LLVM-Set-Visibility [global _LLVM-Value-Ref] [visibility _LLVM-Visibility]) void?]{
Set the visibility of a global value.}

@defproc[(LLVM-Get-Visibility [global _LLVM-Value-Ref]) _LLVM-Visibility]{
Get the visibility of a global value.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Function Attributes}

@defproc[(LLVM-Create-Enum-Attribute [ctx _LLVM-Context-Ref] [kind-id exact-nonnegative-integer?] [val exact-nonnegative-integer?]) cpointer?]{
Create an enum attribute by kind ID and value.}

@defproc[(LLVM-Create-String-Attribute [ctx _LLVM-Context-Ref] [key string?] [key-length exact-nonnegative-integer?] [value string?] [value-length exact-nonnegative-integer?]) cpointer?]{
Create a string attribute.}

@defproc[(LLVM-Add-Attribute-At-Index [fn _LLVM-Value-Ref] [index exact-nonnegative-integer?] [attr cpointer?]) void?]{
Add an attribute to a function at the given index.  Index 0 is the return
value, indices 1+ are parameters.}

@defproc[(LLVM-Set-Function-Call-Conv [fn _LLVM-Value-Ref] [cc exact-nonnegative-integer?]) void?]{
Set the calling convention for a function.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Functions}

@defproc[(LLVM-Add-Function
           [mod _LLVM-Module-Ref]
           [name string?]
           [type _LLVM-Type-Ref])
         _LLVM-Value-Ref]{
Add a function declaration to @racket[mod] with the given @racket[name]
and function @racket[type].}

@defproc[(LLVM-Get-Param
           [fn _LLVM-Value-Ref]
           [index exact-nonnegative-integer?])
         _LLVM-Value-Ref]{
Return the parameter at @racket[index] of function @racket[fn].}

@; ---------------------------------------------------------------------------
@subsection{Core --- Basic Blocks}

@defproc[(LLVM-Append-Basic-Block-In-Context
           [ctx _LLVM-Context-Ref]
           [fn _LLVM-Value-Ref]
           [name string?])
         _LLVM-Basic-Block-Ref]{
Append a new basic block to function @racket[fn].}

@; ---------------------------------------------------------------------------
@subsection{Core --- IR Builder}

@defproc[(LLVM-Create-Builder-In-Context [ctx _LLVM-Context-Ref])
         _LLVM-Builder-Ref]{
Create an IR builder in @racket[ctx]. Must be freed with
@racket[LLVM-Dispose-Builder].}

@defproc[(LLVM-Position-Builder-At-End
           [builder _LLVM-Builder-Ref]
           [bb _LLVM-Basic-Block-Ref])
         void?]{
Position @racket[builder] at the end of @racket[bb].}

@subsubsection{Integer Arithmetic}

All binary arithmetic instructions take @racket[builder], @racket[lhs],
@racket[rhs], and @racket[name] parameters and return a @racket[_LLVM-Value-Ref].

@defproc[(LLVM-Build-Add [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer add.}
@defproc[(LLVM-Build-Sub [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer subtract.}
@defproc[(LLVM-Build-NSWSub [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer subtract with no signed wrap.}
@defproc[(LLVM-Build-Mul [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer multiply.}
@defproc[(LLVM-Build-NSWMul [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer multiply with no signed wrap.}
@defproc[(LLVM-Build-SDiv [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Signed integer division.}
@defproc[(LLVM-Build-UDiv [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Unsigned integer division.}
@defproc[(LLVM-Build-SRem [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Signed integer remainder.}
@defproc[(LLVM-Build-URem [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Unsigned integer remainder.}
@defproc[(LLVM-Build-Neg [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Integer negation.}

@subsubsection{Floating Point Arithmetic}

@defproc[(LLVM-Build-FAdd [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Floating point add.}
@defproc[(LLVM-Build-FSub [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Floating point subtract.}
@defproc[(LLVM-Build-FMul [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Floating point multiply.}
@defproc[(LLVM-Build-FDiv [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Floating point divide.}
@defproc[(LLVM-Build-FNeg [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Floating point negation.}

@subsubsection{Bitwise}

@defproc[(LLVM-Build-And [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Bitwise AND.}
@defproc[(LLVM-Build-Or [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Bitwise OR.}
@defproc[(LLVM-Build-Xor [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Bitwise XOR.}
@defproc[(LLVM-Build-Shl [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Shift left.}
@defproc[(LLVM-Build-LShr [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Logical shift right (zero-fill).}
@defproc[(LLVM-Build-AShr [builder _LLVM-Builder-Ref] [lhs _LLVM-Value-Ref] [rhs _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Arithmetic shift right (sign-extending).}
@defproc[(LLVM-Build-Not [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [name string?]) _LLVM-Value-Ref]{Bitwise NOT (ones' complement).}

@subsubsection{Comparisons}

@defproc[(LLVM-Build-ICmp
           [builder _LLVM-Builder-Ref]
           [predicate _LLVM-Int-Predicate]
           [lhs _LLVM-Value-Ref]
           [rhs _LLVM-Value-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Integer comparison.  Returns an @tt{i1} value.  Predicates:
@racket['LLVMIntEQ], @racket['LLVMIntNE],
@racket['LLVMIntUGT], @racket['LLVMIntUGE], @racket['LLVMIntULT], @racket['LLVMIntULE] (unsigned),
@racket['LLVMIntSGT], @racket['LLVMIntSGE], @racket['LLVMIntSLT], @racket['LLVMIntSLE] (signed).}

@defproc[(LLVM-Build-FCmp
           [builder _LLVM-Builder-Ref]
           [predicate _LLVM-Real-Predicate]
           [lhs _LLVM-Value-Ref]
           [rhs _LLVM-Value-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Floating point comparison.  Returns an @tt{i1} value.  Common predicates:
@racket['LLVMRealOEQ] (ordered equal),
@racket['LLVMRealOGT], @racket['LLVMRealOGE], @racket['LLVMRealOLT], @racket['LLVMRealOLE] (ordered),
@racket['LLVMRealONE] (ordered not equal),
@racket['LLVMRealORD] (ordered, no NaNs),
@racket['LLVMRealUNO] (unordered, either is NaN).}

@subsubsection{Control Flow}

@defproc[(LLVM-Build-Br
           [builder _LLVM-Builder-Ref]
           [dest _LLVM-Basic-Block-Ref])
         _LLVM-Value-Ref]{
Build an unconditional branch to @racket[dest].}

@defproc[(LLVM-Build-Cond-Br
           [builder _LLVM-Builder-Ref]
           [cond _LLVM-Value-Ref]
           [then-bb _LLVM-Basic-Block-Ref]
           [else-bb _LLVM-Basic-Block-Ref])
         _LLVM-Value-Ref]{
Build a conditional branch.  @racket[cond] must be an @tt{i1} value.}

@defproc[(LLVM-Build-Switch
           [builder _LLVM-Builder-Ref]
           [val _LLVM-Value-Ref]
           [else-bb _LLVM-Basic-Block-Ref]
           [num-cases exact-nonnegative-integer?])
         _LLVM-Value-Ref]{
Build a switch instruction with @racket[num-cases] expected cases.
Add cases with @racket[LLVM-Add-Case].  @racket[else-bb] is the default.}

@defproc[(LLVM-Add-Case
           [switch _LLVM-Value-Ref]
           [on-val _LLVM-Value-Ref]
           [dest _LLVM-Basic-Block-Ref])
         void?]{
Add a case to a switch instruction.  @racket[on-val] must be a constant.}

@defproc[(LLVM-Build-Phi
           [builder _LLVM-Builder-Ref]
           [type _LLVM-Type-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Build a phi node.  Add incoming edges with @racket[LLVM-Add-Incoming].}

@defproc[(LLVM-Add-Incoming
           [phi _LLVM-Value-Ref]
           [values (listof _LLVM-Value-Ref)]
           [blocks (listof _LLVM-Basic-Block-Ref)]
           [count exact-nonnegative-integer?])
         void?]{
Add incoming values and their corresponding predecessor blocks to a phi node.
@racket[count] must equal the length of both lists.}

@defproc[(LLVM-Build-Select
           [builder _LLVM-Builder-Ref]
           [cond _LLVM-Value-Ref]
           [then-val _LLVM-Value-Ref]
           [else-val _LLVM-Value-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Build a select (ternary) instruction.  Equivalent to @tt{cond ? then : else}
without branching.  @racket[cond] must be an @tt{i1} value.}

@defproc[(LLVM-Build-Unreachable [builder _LLVM-Builder-Ref]) _LLVM-Value-Ref]{
Build an unreachable instruction, indicating this point should never be reached.}

@subsubsection{Cast / Conversion}

All cast instructions take @racket[builder], @racket[val],
@racket[dest-type], and @racket[name] parameters and return a
@racket[_LLVM-Value-Ref].

@defproc[(LLVM-Build-Trunc [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Truncate integer to a narrower type.}
@defproc[(LLVM-Build-ZExt [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Zero-extend integer to a wider type.}
@defproc[(LLVM-Build-SExt [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Sign-extend integer to a wider type.}
@defproc[(LLVM-Build-FPTo-UI [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Floating point to unsigned integer.}
@defproc[(LLVM-Build-FPTo-SI [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Floating point to signed integer.}
@defproc[(LLVM-Build-UITo-FP [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Unsigned integer to floating point.}
@defproc[(LLVM-Build-SITo-FP [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Signed integer to floating point.}
@defproc[(LLVM-Build-Bit-Cast [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Bitwise reinterpretation (same size, different type).}
@defproc[(LLVM-Build-Int-To-Ptr [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Integer to pointer.}
@defproc[(LLVM-Build-Ptr-To-Int [builder _LLVM-Builder-Ref] [val _LLVM-Value-Ref] [dest-type _LLVM-Type-Ref] [name string?]) _LLVM-Value-Ref]{Pointer to integer.}

@subsubsection{Function Calls}

@defproc[(LLVM-Build-Call2
           [builder _LLVM-Builder-Ref]
           [fn-type _LLVM-Type-Ref]
           [fn _LLVM-Value-Ref]
           [args (listof _LLVM-Value-Ref)]
           [num-args exact-nonnegative-integer?]
           [name string?])
         _LLVM-Value-Ref]{
Call function @racket[fn] with @racket[args].  @racket[fn-type] is the
function's type (required for opaque pointer support).  @racket[num-args]
must equal @racket[(length args)].  Use @racket[""] for @racket[name]
when the function returns @tt{void}.}

@subsubsection{Memory}

@defproc[(LLVM-Build-Alloca
           [builder _LLVM-Builder-Ref]
           [type _LLVM-Type-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Allocate stack space for a value of @racket[type].  Returns a pointer.}

@defproc[(LLVM-Build-Load2
           [builder _LLVM-Builder-Ref]
           [type _LLVM-Type-Ref]
           [ptr _LLVM-Value-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Load a value of @racket[type] from @racket[ptr].  Uses the opaque-pointer
compatible @tt{LLVMBuildLoad2}.}

@defproc[(LLVM-Build-Store
           [builder _LLVM-Builder-Ref]
           [val _LLVM-Value-Ref]
           [ptr _LLVM-Value-Ref])
         _LLVM-Value-Ref]{
Store @racket[val] to @racket[ptr].}

@defproc[(LLVM-Build-GEP2
           [builder _LLVM-Builder-Ref]
           [type _LLVM-Type-Ref]
           [ptr _LLVM-Value-Ref]
           [indices (listof _LLVM-Value-Ref)]
           [num-indices exact-nonnegative-integer?]
           [name string?])
         _LLVM-Value-Ref]{
Compute a pointer to a sub-element of an aggregate (struct field, array
element).  @racket[type] is the source element type.  @racket[indices]
are the GEP indices (the first indexes into the pointer, subsequent
indices index into aggregate types).}

@subsubsection{Terminators}

@defproc[(LLVM-Build-Ret
           [builder _LLVM-Builder-Ref]
           [val _LLVM-Value-Ref])
         _LLVM-Value-Ref]{
Build a return instruction.}

@defproc[(LLVM-Build-Ret-Void [builder _LLVM-Builder-Ref]) _LLVM-Value-Ref]{
Build a void return instruction (for functions returning @tt{void}).}

@defproc[(LLVM-Dispose-Builder [builder _LLVM-Builder-Ref]) void?]{
Dispose of an IR builder.}

@; ---------------------------------------------------------------------------
@subsection{Core --- Memory Buffers}

@defproc[(LLVM-Get-Buffer-Start [buf _LLVM-Memory-Buffer-Ref]) cpointer?]{
Return a pointer to the start of the buffer's data. Cast to @racket[_string]
to read text output (e.g., assembly).}

@defproc[(LLVM-Get-Buffer-Size [buf _LLVM-Memory-Buffer-Ref])
         exact-nonnegative-integer?]{
Return the size of the buffer in bytes.}

@defproc[(LLVM-Dispose-Memory-Buffer [buf _LLVM-Memory-Buffer-Ref]) void?]{
Free a memory buffer.}

@; ---------------------------------------------------------------------------
@subsection{Analysis --- Module Verification}

@defproc[(LLVM-Verify-Module
           [mod _LLVM-Module-Ref]
           [action _LLVM-Verifier-Failure-Action])
         void?]{
Verify @racket[mod] for correctness. Raises @racket[exn:fail] with
the LLVM error message if verification fails.}

@; ---------------------------------------------------------------------------
@subsection{Target Initialization}

These functions initialize LLVM's X86 backend. They must be called before
creating target machines or JIT engines.

@defproc[(Initialize-Native-Target!) void?]{
Convenience function that calls all five X86 initialization functions below.
Equivalent to the C @tt{LLVMInitializeNativeTarget} inline function.}

@defproc[(LLVM-Initialize-X86-Target-Info) void?]{Initialize X86 target info.}
@defproc[(LLVM-Initialize-X86-Target) void?]{Initialize X86 target.}
@defproc[(LLVM-Initialize-X86-Target-MC) void?]{Initialize X86 target MC layer.}
@defproc[(LLVM-Initialize-X86-Asm-Printer) void?]{Initialize X86 assembly printer.}
@defproc[(LLVM-Initialize-X86-Asm-Parser) void?]{Initialize X86 assembly parser.}
@defproc[(LLVM-Initialize-X86-Disassembler) void?]{Initialize X86 disassembler.}

@; ---------------------------------------------------------------------------
@subsection{Target Machine}

@defproc[(LLVM-Get-Default-Target-Triple) cpointer?]{
Return the default target triple as a C string pointer. Free with
@racket[LLVM-Dispose-Message].}

@defproc[(LLVM-Get-Target-From-Triple [triple string?])
         _LLVM-Target-Ref]{
Look up a target by @racket[triple]. Raises @racket[exn:fail] if the
triple is not recognized.}

@defproc[(LLVM-Create-Target-Machine
           [target _LLVM-Target-Ref]
           [triple string?]
           [cpu string?]
           [features string?]
           [opt-level _LLVM-Code-Gen-Opt-Level]
           [reloc-mode _LLVM-Reloc-Mode]
           [code-model _LLVM-Code-Model])
         _LLVM-Target-Machine-Ref]{
Create a target machine. Pass @racket["generic"] for @racket[cpu] and
@racket[""] for @racket[features] as defaults.}

@defproc[(LLVM-Dispose-Target-Machine [tm _LLVM-Target-Machine-Ref]) void?]{
Dispose of a target machine.}

@defproc[(LLVM-Target-Machine-Emit-To-Memory-Buffer
           [tm _LLVM-Target-Machine-Ref]
           [mod _LLVM-Module-Ref]
           [file-type _LLVM-Code-Gen-File-Type])
         _LLVM-Memory-Buffer-Ref]{
Emit @racket[mod] as assembly or object code into a memory buffer.
Pass @racket['LLVMAssemblyFile] for assembly text or
@racket['LLVMObjectFile] for machine code.  Raises @racket[exn:fail]
on error.  Read the result with @racket[LLVM-Get-Buffer-Start] and
@racket[LLVM-Get-Buffer-Size].}

@defproc[(LLVM-Target-Machine-Emit-To-File
           [tm _LLVM-Target-Machine-Ref]
           [mod _LLVM-Module-Ref]
           [filename string?]
           [file-type _LLVM-Code-Gen-File-Type])
         void?]{
Emit @racket[mod] as assembly or object code to @racket[filename].
Raises @racket[exn:fail] on error.}

@; ---------------------------------------------------------------------------
@subsection{Execution Engine (MCJIT --- Deprecated)}

@bold{Deprecated.}  MCJIT is the legacy JIT engine.  It compiles an
entire module at once and does not support incremental compilation.
Use the ORC JIT (LLJIT) instead for new code.

@defproc[(LLVM-Link-In-MCJIT) void?]{
Link in the MCJIT engine. Must be called once before creating an MCJIT
execution engine.}

@defproc[(make-LLVM-MCJIT-Compiler-Options
           [OptLevel exact-nonnegative-integer?]
           [CodeModel _LLVM-Code-Model]
           [NoFramePointerElim _LLVM-Bool]
           [EnableFastISel _LLVM-Bool]
           [MCJMM (or/c cpointer? #f)])
         _LLVM-MCJIT-Compiler-Options-pointer]{
Allocate an @tt{LLVMMCJITCompilerOptions} struct. Typically followed by
@racket[LLVM-Initialize-MCJIT-Compiler-Options] to set safe defaults.}

@defthing[_LLVM-MCJIT-Compiler-Options ctype?]{
C struct type for MCJIT compiler options. Fields:
@itemlist[
  @item{@tt{OptLevel} --- @racket[_uint]}
  @item{@tt{CodeModel} --- @racket[_LLVM-Code-Model]}
  @item{@tt{NoFramePointerElim} --- @racket[_LLVM-Bool]}
  @item{@tt{EnableFastISel} --- @racket[_LLVM-Bool]}
  @item{@tt{MCJMM} --- @racket[_pointer] (custom memory manager, or @racket[#f])}
]}

@defproc[(LLVM-Initialize-MCJIT-Compiler-Options
           [opts _LLVM-MCJIT-Compiler-Options-pointer]
           [size exact-nonnegative-integer?])
         void?]{
Initialize @racket[opts] to safe defaults. Pass
@racket[(ctype-sizeof _LLVM-MCJIT-Compiler-Options)] for @racket[size].}

@defproc[(LLVM-Create-MCJIT-Compiler-For-Module
           [mod _LLVM-Module-Ref]
           [opts _LLVM-MCJIT-Compiler-Options-pointer]
           [size exact-nonnegative-integer?])
         _LLVM-Execution-Engine-Ref]{
Create an MCJIT execution engine for @racket[mod].  Module ownership
transfers to the engine --- do @bold{not} dispose the module separately.
Raises @racket[exn:fail] on error.}

@defproc[(LLVM-Get-Function-Address
           [ee _LLVM-Execution-Engine-Ref]
           [name string?])
         exact-nonnegative-integer?]{
Return the address of the JIT'd function @racket[name] as a @racket[_uint64].
Returns @racket[0] if the function is not found. Cast the result to a
callable function pointer with @racket[cast]:

@racketblock[
(define addr (LLVM-Get-Function-Address ee "add"))
(define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4)
]}

@defproc[(LLVM-Dispose-Execution-Engine [ee _LLVM-Execution-Engine-Ref]) void?]{
Dispose of an execution engine and all modules it owns.}

@defproc[(LLVM-Create-Generic-Value-Of-Int
           [ty _LLVM-Type-Ref]
           [n exact-nonnegative-integer?]
           [is-signed _LLVM-Bool])
         _LLVM-Generic-Value-Ref]{
Box an integer value for use with @racket[LLVM-Run-Function].}

@defproc[(LLVM-Run-Function
           [ee _LLVM-Execution-Engine-Ref]
           [fn _LLVM-Value-Ref]
           [num-args exact-nonnegative-integer?]
           [args (listof _LLVM-Generic-Value-Ref)])
         _LLVM-Generic-Value-Ref]{
Call a JIT'd function with boxed arguments. Returns a boxed result.}

@defproc[(LLVM-Generic-Value-To-Int
           [val _LLVM-Generic-Value-Ref]
           [is-signed _LLVM-Bool])
         exact-nonnegative-integer?]{
Unbox a generic value as an integer.}

@defproc[(LLVM-Dispose-Generic-Value [val _LLVM-Generic-Value-Ref]) void?]{
Dispose of a generic value.}

@; ---------------------------------------------------------------------------
@subsection{Optimization Passes}

@subsubsection{New Pass Manager (LLVM 13+)}

The new pass manager uses a string-based pipeline description
(e.g., @racket["default<O2>"], @racket["mem2reg"], @racket["instcombine,gvn"]).
This is the preferred API.

@defproc[(LLVM-Create-Pass-Builder-Options) _LLVM-Pass-Builder-Options-Ref]{
Create pass builder options.  GC-managed.}

@defproc[(LLVM-Dispose-Pass-Builder-Options [opts _LLVM-Pass-Builder-Options-Ref]) void?]{
Dispose of pass builder options.}

@defproc[(LLVM-Run-Passes
           [mod _LLVM-Module-Ref]
           [passes string?]
           [tm _LLVM-Target-Machine-Ref]
           [opts _LLVM-Pass-Builder-Options-Ref])
         void?]{
Run the named optimization passes on @racket[mod].  Raises @racket[exn:fail]
if the pipeline description is invalid or a pass fails.

Common pipelines: @racket["default<O0>"], @racket["default<O1>"],
@racket["default<O2>"], @racket["default<O3>"].
Individual passes: @racket["mem2reg"], @racket["instcombine"],
@racket["gvn"], @racket["simplifycfg"].
Combine with commas: @racket["mem2reg,instcombine,gvn"].}

@subsubsection{Legacy Pass Manager (Deprecated)}

@bold{Deprecated.}  The legacy pass manager and its transform passes are
deprecated as of LLVM 14 and are being removed in newer LLVM versions.
Use the new pass manager (@racket[LLVM-Run-Passes]) instead.  These
bindings are provided for compatibility with LLVM 15 and earlier.

@defproc[(LLVM-Create-Pass-Manager) _LLVM-Pass-Manager-Ref]{
Create a module-level pass manager.  GC-managed.}

@defproc[(LLVM-Create-Function-Pass-Manager-For-Module
           [mod _LLVM-Module-Ref])
         _LLVM-Pass-Manager-Ref]{
Create a function-level pass manager for @racket[mod].  GC-managed.}

@defproc[(LLVM-Dispose-Pass-Manager [pm _LLVM-Pass-Manager-Ref]) void?]{
Dispose of a pass manager.}

@defproc[(LLVM-Run-Pass-Manager
           [pm _LLVM-Pass-Manager-Ref]
           [mod _LLVM-Module-Ref])
         _LLVM-Bool]{
Run all module passes.  Returns non-zero if any pass modified the module.}

@defproc[(LLVM-Initialize-Function-Pass-Manager [fpm _LLVM-Pass-Manager-Ref]) _LLVM-Bool]{
Initialize function pass manager before running passes.}

@defproc[(LLVM-Run-Function-Pass-Manager
           [fpm _LLVM-Pass-Manager-Ref]
           [fn _LLVM-Value-Ref])
         _LLVM-Bool]{
Run function passes on @racket[fn].  Returns non-zero if the function was modified.}

@defproc[(LLVM-Finalize-Function-Pass-Manager [fpm _LLVM-Pass-Manager-Ref]) _LLVM-Bool]{
Finalize function pass manager after running passes.}

@subsubsection{Legacy Transform Passes (Deprecated)}

These add individual optimization passes to a legacy pass manager.
Prefer using @racket[LLVM-Run-Passes] with pass name strings
(e.g., @racket["instcombine"], @racket["gvn"], @racket["mem2reg"]).

@defproc[(LLVM-Add-Instruction-Combining-Pass [pm _LLVM-Pass-Manager-Ref]) void?]{Add instruction combining.}
@defproc[(LLVM-Add-Reassociate-Pass [pm _LLVM-Pass-Manager-Ref]) void?]{Add expression reassociation.}
@defproc[(LLVM-Add-GVN-Pass [pm _LLVM-Pass-Manager-Ref]) void?]{Add global value numbering.}
@defproc[(LLVM-Add-CFG-Simplification-Pass [pm _LLVM-Pass-Manager-Ref]) void?]{Add control flow graph simplification.}
@defproc[(LLVM-Add-Promote-Memory-To-Register-Pass [pm _LLVM-Pass-Manager-Ref]) void?]{Add mem2reg (promote allocas to SSA registers).}
@defproc[(LLVM-Add-Scalar-Repl-Aggregates-Pass-SSA [pm _LLVM-Pass-Manager-Ref]) void?]{Add scalar replacement of aggregates (SROA).}

@; ---------------------------------------------------------------------------
@subsection{Bitcode I/O}

@subsubsection{BitWriter}

@defproc[(LLVM-Write-Bitcode-To-File [mod _LLVM-Module-Ref] [path string?]) void?]{
Write @racket[mod] as bitcode to @racket[path].  Raises @racket[exn:fail] on error.}

@defproc[(LLVM-Write-Bitcode-To-Memory-Buffer [mod _LLVM-Module-Ref]) _LLVM-Memory-Buffer-Ref]{
Write @racket[mod] as bitcode to a memory buffer.  GC-managed.}

@subsubsection{BitReader}

@defproc[(LLVM-Parse-Bitcode-In-Context2
           [ctx _LLVM-Context-Ref]
           [buf _LLVM-Memory-Buffer-Ref])
         _LLVM-Module-Ref]{
Parse a bitcode memory buffer into a module in @racket[ctx].
Raises @racket[exn:fail] on error.  The returned module is GC-managed
and anchored to @racket[ctx].}

@defproc[(LLVM-Parse-Bitcode-File [ctx _LLVM-Context-Ref] [path string?])
         _LLVM-Module-Ref]{
Convenience: read a bitcode file into a module.  Equivalent to loading
the file into a memory buffer and calling @racket[LLVM-Parse-Bitcode-In-Context2].}

@subsubsection{IRReader}

@defproc[(LLVM-Parse-IR-In-Context
           [ctx _LLVM-Context-Ref]
           [buf _LLVM-Memory-Buffer-Ref])
         _LLVM-Module-Ref]{
Parse LLVM IR text (a @tt{.ll} file) from a memory buffer into a module.
Raises @racket[exn:fail] with the parse error on failure.  The returned
module is GC-managed and anchored to @racket[ctx].
Note: this consumes @racket[buf] --- do not use it after this call.}

@subsubsection{Memory Buffer Construction}

@defproc[(LLVM-Create-Memory-Buffer-With-Contents-Of-File [path string?])
         _LLVM-Memory-Buffer-Ref]{
Read a file into a memory buffer.  Raises @racket[exn:fail] on error.  GC-managed.}

@defproc[(LLVM-Create-Memory-Buffer-With-Memory-Range
           [data string?]
           [length exact-nonnegative-integer?]
           [name string?]
           [requires-null-terminator _LLVM-Bool])
         _LLVM-Memory-Buffer-Ref]{
Create a memory buffer from in-memory data.  @racket[name] is used for
diagnostics.  GC-managed.  Note: LLVM references @racket[data] without
copying --- ensure the string remains valid while the buffer is in use.}

@subsubsection{Module Utilities}

@defproc[(LLVM-Clone-Module [mod _LLVM-Module-Ref]) _LLVM-Module-Ref]{
Create a deep copy of @racket[mod].  The clone is GC-managed and anchored
to the original module (transitively to its context).}

@defproc[(LLVM-Set-Target [mod _LLVM-Module-Ref] [triple string?]) void?]{
Set the target triple for @racket[mod].}

@defproc[(LLVM-Get-Target [mod _LLVM-Module-Ref]) string?]{
Get the target triple of @racket[mod].}

@defproc[(LLVM-Set-Data-Layout [mod _LLVM-Module-Ref] [layout string?]) void?]{
Set the data layout string for @racket[mod].}

@defproc[(LLVM-Get-Data-Layout [mod _LLVM-Module-Ref]) string?]{
Get the data layout string of @racket[mod].}

@; ---------------------------------------------------------------------------
@subsection{Linker}

@defproc[(LLVM-Link-Modules2
           [dest _LLVM-Module-Ref]
           [src _LLVM-Module-Ref])
         void?]{
Link @racket[src] into @racket[dest].  All definitions from @racket[src]
are merged into @racket[dest].  @racket[src] is consumed and must not be
used after this call.  Raises @racket[exn:fail] on error (e.g., conflicting
symbol definitions).}

@; ---------------------------------------------------------------------------
@subsection{Object File Inspection}

Inspect compiled object files (sections, symbols, relocations).

@defproc[(LLVM-Create-Object-File [buf _LLVM-Memory-Buffer-Ref])
         _LLVM-Object-File-Ref]{
Create an object file from a memory buffer.  Consumes @racket[buf].
Raises @racket[exn:fail] if the buffer is not a valid object file.
GC-managed.}

@defproc[(LLVM-Dispose-Object-File [obj _LLVM-Object-File-Ref]) void?]{
Dispose of an object file.}

@defproc[(LLVM-Object-File-Sections [obj _LLVM-Object-File-Ref])
         list?]{
Return a list of all sections in @racket[obj].  Each element is a
@tt{section-info} struct with @tt{section-info-name},
@tt{section-info-size}, and @tt{section-info-address} fields.}

@defproc[(LLVM-Object-File-Symbols [obj _LLVM-Object-File-Ref])
         list?]{
Return a list of all symbols in @racket[obj].  Each element is a
@tt{symbol-info} struct with @tt{symbol-info-name},
@tt{symbol-info-address}, and @tt{symbol-info-size} fields.}

@defproc[(LLVM-Section-Relocations [section-iter _LLVM-Section-Iterator-Ref])
         list?]{
Return a list of all relocations for the section at the current iterator
position.  Each element is a @tt{relocation-info} struct with
@tt{relocation-info-offset}, @tt{relocation-info-type}, and
@tt{relocation-info-type-name} fields.  Use with the low-level
section iterator API.}

Low-level iterator functions are also available for sections
(@tt{LLVM-Get-Sections}, @tt{LLVM-Move-To-Next-Section}, etc.),
symbols (@tt{LLVM-Get-Symbols}, @tt{LLVM-Move-To-Next-Symbol}, etc.),
and relocations (@tt{LLVM-Get-Relocations},
@tt{LLVM-Move-To-Next-Relocation}, etc.).

@; ---------------------------------------------------------------------------
@subsection{Debug Info (DIBuilder)}

Emit DWARF debug information metadata into LLVM IR.

@defproc[(LLVM-Create-DI-Builder [mod _LLVM-Module-Ref]) _LLVM-DI-Builder-Ref]{
Create a debug info builder for @racket[mod].  GC-managed.  Call
@racket[LLVM-DI-Builder-Finalize] before disposing.}

@defproc[(LLVM-Dispose-DI-Builder [dib _LLVM-DI-Builder-Ref]) void?]{
Dispose of a debug info builder.}

@defproc[(LLVM-DI-Builder-Finalize [dib _LLVM-DI-Builder-Ref]) void?]{
Finalize all debug info.  Must be called before the module is emitted
or verified with debug info.}

@defproc[(LLVM-DI-Builder-Create-File
           [dib _LLVM-DI-Builder-Ref]
           [filename string?]
           [directory string?])
         _LLVM-Metadata-Ref]{
Create a file descriptor for debug info.}

@defproc[(LLVM-DI-Builder-Create-Compile-Unit
           [dib _LLVM-DI-Builder-Ref]
           [lang _LLVM-DWARF-Source-Language]
           [file _LLVM-Metadata-Ref]
           [producer string?]
           [is-optimized _LLVM-Bool]
           [flags string?]
           [runtime-ver exact-nonnegative-integer?]
           [split-name string?]
           [emission-kind _LLVM-DWARF-Emission-Kind]
           [dwo-id exact-nonnegative-integer?]
           [split-debug-inlining _LLVM-Bool]
           [debug-info-for-profiling _LLVM-Bool])
         _LLVM-Metadata-Ref]{
Create a compile unit.  This is the root of the debug info hierarchy.}

@defproc[(LLVM-DI-Builder-Create-Function
           [dib _LLVM-DI-Builder-Ref]
           [scope _LLVM-Metadata-Ref]
           [name string?]
           [linkage-name string?]
           [file _LLVM-Metadata-Ref]
           [line exact-nonnegative-integer?]
           [type _LLVM-Metadata-Ref]
           [is-local _LLVM-Bool]
           [is-definition _LLVM-Bool]
           [scope-line exact-nonnegative-integer?]
           [flags exact-nonnegative-integer?]
           [is-optimized _LLVM-Bool])
         _LLVM-Metadata-Ref]{
Create debug info for a function (subprogram).  Attach to the IR
function with @racket[LLVM-Set-Subprogram].}

@defproc[(LLVM-DI-Builder-Create-Lexical-Block
           [dib _LLVM-DI-Builder-Ref]
           [scope _LLVM-Metadata-Ref]
           [file _LLVM-Metadata-Ref]
           [line exact-nonnegative-integer?]
           [column exact-nonnegative-integer?])
         _LLVM-Metadata-Ref]{
Create a lexical block scope for debug info.}

@defproc[(LLVM-DI-Builder-Create-Basic-Type
           [dib _LLVM-DI-Builder-Ref]
           [name string?]
           [size-in-bits exact-nonnegative-integer?]
           [encoding exact-nonnegative-integer?]
           [flags exact-nonnegative-integer?])
         _LLVM-Metadata-Ref]{
Create debug info for a basic type.  Common encodings: 5 (signed),
7 (unsigned), 4 (float).}

@defproc[(LLVM-DI-Builder-Create-Subroutine-Type
           [dib _LLVM-DI-Builder-Ref]
           [file _LLVM-Metadata-Ref]
           [param-types (listof _LLVM-Metadata-Ref)]
           [num-params exact-nonnegative-integer?]
           [flags exact-nonnegative-integer?])
         _LLVM-Metadata-Ref]{
Create debug info for a function type.  The first element of
@racket[param-types] is the return type.}

@defproc[(LLVM-DI-Builder-Create-Debug-Location
           [ctx _LLVM-Context-Ref]
           [line exact-nonnegative-integer?]
           [column exact-nonnegative-integer?]
           [scope _LLVM-Metadata-Ref]
           [inlined-at (or/c _LLVM-Metadata-Ref #f)])
         _LLVM-Metadata-Ref]{
Create a debug source location.  Pass @racket[#f] for @racket[inlined-at]
if not inlined.}

@defproc[(LLVM-Set-Subprogram [fn _LLVM-Value-Ref] [sp _LLVM-Metadata-Ref]) void?]{
Attach a subprogram (function debug info) to an IR function.}

@defproc[(LLVM-Set-Current-Debug-Location2
           [builder _LLVM-Builder-Ref]
           [loc _LLVM-Metadata-Ref])
         void?]{
Set the current debug location on the builder.  All subsequent
instructions will be annotated with this location.}

@; ---------------------------------------------------------------------------
@subsection{Disassembler}

Disassemble machine code bytes to assembly text.

@defproc[(LLVM-Create-Disasm [triple string?]) cpointer?]{
Create a disassembler for the given target triple.  Uses the "generic"
CPU.  Raises @racket[exn:fail] if the target is not supported.
GC-managed.  Requires @racket[Initialize-Native-Target!] to have been
called.}

@defproc[(LLVM-Disasm-Dispose [dc cpointer?]) void?]{
Dispose of a disassembler context.}

@defproc[(LLVM-Disasm-Instruction
           [dc cpointer?]
           [bytes (or/c bytes? cpointer?)]
           [size exact-nonnegative-integer?]
           [pc exact-nonnegative-integer?])
         (or/c string? #f)]{
Disassemble one instruction from @racket[bytes].  Returns the assembly
text on success, or @racket[#f] if the bytes couldn't be decoded.
@racket[pc] is the virtual address used for PC-relative calculations.}

@defproc[(LLVM-Set-Disasm-Options
           [dc cpointer?]
           [options exact-nonnegative-integer?])
         void?]{
Set disassembler options.  Common values: @racket[1] (markup),
@racket[2] (print immediates as hex), @racket[4] (print latency).}

@; ---------------------------------------------------------------------------
@subsection{ORC JIT}

The ORC JIT is the modern replacement for MCJIT.  It supports
incremental compilation and lazy materialization.

@subsubsection{Thread-Safe Context}

@defproc[(LLVM-Orc-Create-New-Thread-Safe-Context) _LLVM-Orc-Thread-Safe-Context-Ref]{
Create a new thread-safe context.  GC-managed.}

@defproc[(LLVM-Orc-Dispose-Thread-Safe-Context [ts-ctx _LLVM-Orc-Thread-Safe-Context-Ref]) void?]{
Dispose of a thread-safe context.}

@defproc[(LLVM-Orc-Thread-Safe-Context-Get-Context
           [ts-ctx _LLVM-Orc-Thread-Safe-Context-Ref])
         _LLVM-Context-Ref]{
Get the underlying LLVM context.  The context is owned by
@racket[ts-ctx] --- do not dispose it separately.}

@subsubsection{Thread-Safe Module}

@defproc[(LLVM-Orc-Create-New-Thread-Safe-Module
           [mod _LLVM-Module-Ref]
           [ts-ctx _LLVM-Orc-Thread-Safe-Context-Ref])
         _LLVM-Orc-Thread-Safe-Module-Ref]{
Wrap @racket[mod] in a thread-safe module.  Takes ownership of
@racket[mod] --- do not dispose it separately.  GC-managed.}

@defproc[(LLVM-Orc-Dispose-Thread-Safe-Module [ts-mod _LLVM-Orc-Thread-Safe-Module-Ref]) void?]{
Dispose of a thread-safe module.}

@subsubsection{LLJIT}

@defproc[(LLVM-Orc-Create-LLJIT [builder (or/c cpointer? #f)]) _LLVM-Orc-LLJIT-Ref]{
Create an LLJIT instance.  Pass @racket[#f] for @racket[builder] to
use default settings.  Raises @racket[exn:fail] on error.  GC-managed.}

@defproc[(LLVM-Orc-Dispose-LLJIT [jit _LLVM-Orc-LLJIT-Ref]) void?]{
Dispose of an LLJIT instance.  Raises @racket[exn:fail] if disposal fails.}

@defproc[(LLVM-Orc-LLJIT-Get-Main-JIT-Dylib [jit _LLVM-Orc-LLJIT-Ref])
         _LLVM-Orc-JIT-Dylib-Ref]{
Get the main JIT dynamic library for adding modules.}

@defproc[(LLVM-Orc-LLJIT-Get-Execution-Session [jit _LLVM-Orc-LLJIT-Ref])
         _LLVM-Orc-Execution-Session-Ref]{
Get the execution session for this LLJIT instance.}

@defproc[(LLVM-Orc-LLJIT-Get-Triple-String [jit _LLVM-Orc-LLJIT-Ref]) string?]{
Get the target triple string for this LLJIT instance.}

@defproc[(LLVM-Orc-LLJIT-Add-LLVM-IR-Module
           [jit _LLVM-Orc-LLJIT-Ref]
           [dylib _LLVM-Orc-JIT-Dylib-Ref]
           [ts-mod _LLVM-Orc-Thread-Safe-Module-Ref])
         void?]{
Add a thread-safe module to @racket[dylib].  Takes ownership of
@racket[ts-mod].  Raises @racket[exn:fail] on error.}

@defproc[(LLVM-Orc-LLJIT-Lookup
           [jit _LLVM-Orc-LLJIT-Ref]
           [name string?])
         exact-nonnegative-integer?]{
Look up a symbol by @racket[name] and return its address as a
@racket[_uint64].  Raises @racket[exn:fail] if the symbol is not found.
Cast the result to a callable function pointer with @racket[cast].}

@; ---------------------------------------------------------------------------
@subsection{Module Iteration}

Walk the functions, globals, basic blocks, and instructions in a module.

@defproc[(LLVM-Module-Functions [mod _LLVM-Module-Ref]) (listof _LLVM-Value-Ref)]{
Return a list of all functions in @racket[mod].}

@defproc[(LLVM-Module-Globals [mod _LLVM-Module-Ref]) (listof _LLVM-Value-Ref)]{
Return a list of all global variables in @racket[mod].}

@defproc[(LLVM-Function-Basic-Blocks [fn _LLVM-Value-Ref]) (listof _LLVM-Basic-Block-Ref)]{
Return a list of all basic blocks in function @racket[fn].}

@defproc[(LLVM-Basic-Block-Instructions [bb _LLVM-Basic-Block-Ref]) (listof _LLVM-Value-Ref)]{
Return a list of all instructions in basic block @racket[bb].}

@defproc[(LLVM-Get-Value-Name [val _LLVM-Value-Ref]) string?]{
Get the name of a value (function, global, instruction, etc.).}

@defproc[(LLVM-Get-Instruction-Opcode [inst _LLVM-Value-Ref]) exact-integer?]{
Get the opcode of an instruction as an integer.}

Low-level iteration functions are also available:
@tt{LLVM-Get-First-Function} / @tt{LLVM-Get-Next-Function},
@tt{LLVM-Get-First-Global} / @tt{LLVM-Get-Next-Global},
@tt{LLVM-Get-First-Basic-Block} / @tt{LLVM-Get-Next-Basic-Block},
@tt{LLVM-Get-First-Instruction} / @tt{LLVM-Get-Next-Instruction}.
Each returns @racket[#f] at the end of the list.

@; ---------------------------------------------------------------------------
@subsection{Optimization Remarks}

Parse YAML-format optimization remarks emitted by LLVM passes.

@defproc[(LLVM-Remark-Parser-Create-YAML [buf cpointer?] [size exact-nonnegative-integer?]) cpointer?]{
Create a remark parser for YAML data.  GC-managed.}

@defproc[(LLVM-Remark-Parser-Dispose [parser cpointer?]) void?]{
Dispose of a remark parser.}

@defproc[(LLVM-Remark-Parser-Get-Next [parser cpointer?]) (or/c cpointer? #f)]{
Get the next remark entry, or @racket[#f] if done.  The entry must be
freed with @racket[LLVM-Remark-Entry-Dispose].}

@defproc[(LLVM-Remark-Parser-Has-Error [parser cpointer?]) boolean?]{
Check if the parser encountered an error.}

@defproc[(LLVM-Remark-Parser-Get-Error-Message [parser cpointer?]) string?]{
Get the error message from the parser.}

@defproc[(LLVM-Remark-Entry-Dispose [entry cpointer?]) void?]{
Dispose of a remark entry.}

@defproc[(LLVM-Remark-Entry-Get-Type [entry cpointer?]) exact-integer?]{
Get the remark type (0=Unknown, 1=Passed, 2=Missed, 3=Analysis, etc.).}

@defproc[(LLVM-Remark-Entry-Get-Pass-Name [entry cpointer?]) cpointer?]{
Get the pass name as a remark string.  Use @racket[LLVM-Remark-String-Get-Data]
to extract.}

@defproc[(LLVM-Remark-Entry-Get-Remark-Name [entry cpointer?]) cpointer?]{
Get the remark identifier as a remark string.}

@defproc[(LLVM-Remark-Entry-Get-Function-Name [entry cpointer?]) cpointer?]{
Get the function name as a remark string.}

@defproc[(LLVM-Remark-String-Get-Data [str cpointer?]) string?]{
Get the string data from a remark string reference.}

@defproc[(LLVM-Remark-String-Get-Len [str cpointer?]) exact-nonnegative-integer?]{
Get the length of a remark string.}

