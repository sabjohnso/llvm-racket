#lang scribble/manual
@require[@for-label[llvm/unsafe
                    ffi/unsafe
                    racket/base]]

@title{llvm}
@author{sbj}

LLVM bindings for Racket via the LLVM C API.

The package provides a thin unsafe FFI layer that maps directly to the
@hyperlink["https://llvm.org/doxygen/group__LLVMC.html"]{LLVM C API}.
Naming follows uppercase-kebab convention: the C function
@tt{LLVMContextCreate} becomes @racket[LLVM-Context-Create].

@local-table-of-contents[]

@; ---------------------------------------------------------------------------
@section{Unsafe FFI Layer}

@defmodule[llvm/unsafe]

This module re-exports every binding from the subsections below.
All functions are unsafe foreign calls --- misuse (wrong types,
use-after-free, double-free) can crash the process.

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

@defproc[(LLVM-Build-Add
           [builder _LLVM-Builder-Ref]
           [lhs _LLVM-Value-Ref]
           [rhs _LLVM-Value-Ref]
           [name string?])
         _LLVM-Value-Ref]{
Build an integer add instruction.}

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
         (values _LLVM-Bool (or/c cpointer? #f))]{
Verify @racket[mod] for correctness. Returns two values:
@itemlist[
  @item{A @racket[_LLVM-Bool] --- @racket[0] on success, non-zero on failure.}
  @item{An error message pointer (free with @racket[LLVM-Dispose-Message])
        or @racket[#f].}
]}

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

@; ---------------------------------------------------------------------------
@subsection{Target Machine}

@defproc[(LLVM-Get-Default-Target-Triple) cpointer?]{
Return the default target triple as a C string pointer. Free with
@racket[LLVM-Dispose-Message].}

@defproc[(LLVM-Get-Target-From-Triple [triple string?])
         (values _LLVM-Bool _LLVM-Target-Ref (or/c cpointer? #f))]{
Look up a target by @racket[triple]. Returns three values:
@itemlist[
  @item{A @racket[_LLVM-Bool] --- @racket[0] on success.}
  @item{The @racket[_LLVM-Target-Ref] (valid only on success).}
  @item{An error message pointer on failure (free with
        @racket[LLVM-Dispose-Message]), or uninitialized on success.}
]}

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
         (values _LLVM-Bool _LLVM-Memory-Buffer-Ref (or/c cpointer? #f))]{
Emit @racket[mod] as assembly or object code into a memory buffer.
Pass @racket['LLVMAssemblyFile] for assembly text or
@racket['LLVMObjectFile] for machine code. Returns three values:
@itemlist[
  @item{A @racket[_LLVM-Bool] --- @racket[0] on success.}
  @item{The @racket[_LLVM-Memory-Buffer-Ref] containing the output (valid only on success).}
  @item{An error message pointer on failure (free with @racket[LLVM-Dispose-Message]).}
]
Read the result with @racket[LLVM-Get-Buffer-Start] and
@racket[LLVM-Get-Buffer-Size]. Free with @racket[LLVM-Dispose-Memory-Buffer].}

@defproc[(LLVM-Target-Machine-Emit-To-File
           [tm _LLVM-Target-Machine-Ref]
           [mod _LLVM-Module-Ref]
           [filename string?]
           [file-type _LLVM-Code-Gen-File-Type])
         (values _LLVM-Bool (or/c cpointer? #f))]{
Emit @racket[mod] as assembly or object code to @racket[filename].
Returns two values:
@itemlist[
  @item{A @racket[_LLVM-Bool] --- @racket[0] on success.}
  @item{An error message pointer on failure (free with @racket[LLVM-Dispose-Message]).}
]}

@; ---------------------------------------------------------------------------
@subsection{Execution Engine (MCJIT)}

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
         (values _LLVM-Bool _LLVM-Execution-Engine-Ref (or/c cpointer? #f))]{
Create an MCJIT execution engine for @racket[mod]. Module ownership
transfers to the engine on success --- do @bold{not} dispose the module
separately. Returns three values:
@itemlist[
  @item{A @racket[_LLVM-Bool] --- @racket[0] on success.}
  @item{The @racket[_LLVM-Execution-Engine-Ref] (valid only on success).}
  @item{An error message pointer on failure (free with
        @racket[LLVM-Dispose-Message]).}
]}

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
@section{Quick Start}

Build an @tt{add(i32, i32) -> i32} function, JIT-compile it, and call it:

@racketblock[
(require llvm/unsafe ffi/unsafe)

(Initialize-Native-Target!)
(LLVM-Link-In-MCJIT)

(define ctx (LLVM-Context-Create))
(define mod (LLVM-Module-Create-With-Name-In-Context "example" ctx))
(define i32 (LLVM-Int32-Type-In-Context ctx))
(define fn-type (LLVM-Function-Type i32 (list i32 i32) 2 0))
(define fn (LLVM-Add-Function mod "add" fn-type))
(define entry (LLVM-Append-Basic-Block-In-Context ctx fn "entry"))
(define builder (LLVM-Create-Builder-In-Context ctx))
(LLVM-Position-Builder-At-End builder entry)
(LLVM-Build-Ret builder
                (LLVM-Build-Add builder
                               (LLVM-Get-Param fn 0)
                               (LLVM-Get-Param fn 1)
                               "tmp"))
(LLVM-Dispose-Builder builder)

(define-values (vfail? verr)
  (LLVM-Verify-Module mod 'LLVMReturnStatusAction))
(when verr (LLVM-Dispose-Message verr))

(define opts
  (make-LLVM-MCJIT-Compiler-Options
   0 'LLVMCodeModelJITDefault 0 0 #f))
(LLVM-Initialize-MCJIT-Compiler-Options
 opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options))
(define-values (efail? ee eerr)
  (LLVM-Create-MCJIT-Compiler-For-Module
   mod opts (ctype-sizeof _LLVM-MCJIT-Compiler-Options)))
(when (and (not (zero? efail?)) eerr)
  (LLVM-Dispose-Message eerr))

(define addr (LLVM-Get-Function-Address ee "add"))
(define add-fn (cast addr _uint64 (_fun _int32 _int32 -> _int32)))
(add-fn 3 4) (code:comment "=> 7")

(LLVM-Dispose-Execution-Engine ee)
(LLVM-Context-Dispose ctx)
]
