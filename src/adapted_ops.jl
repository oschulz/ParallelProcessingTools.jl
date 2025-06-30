# Internal functionality of SolidStateDetectors, not part of the public API:

const _CPUArrayLike = Union{Array, SubArray{<:Any,<:Any,<:Array}}
const _LinIndexCPUArrayLike = Union{Array, SubArray{<:Any,<:Any,<:Array,<:Any,true}}
const _NonLinIndexView = SubArray{<:Any,<:Any,<:Array,<:Any,false}


# Override for adapters that need special handling, to convert them to other adapters:
@inline pp_adapter(to::Adapter) where Adapter = to
@inline pp_adapter(::Type{Adapter}) where Adapter = Adapter
@inline pp_adapter(m::Module) = pp_module_adapter(Val(nameof(m)))

pp_module_adapter(Base.@nospecialize(module_name::Val)) = throw(ArgumentError("No default pp_adapter defined for module $(only(typeof(module_name).parameters))"))


const CurriedAdapt{Adapter} = Base.Fix1{typeof(Adapt.adapt), Adapter}

@inline adaptfunc(to::Adapter) where Adapter = Base.Fix1(Adapt.adapt, pp_adapter(to))
@inline adaptfunc(::Type{Adapter}) where Adapter = Base.Fix1(Adapt.adapt, pp_adapter(Adapter))

# ToDo (maybe): adaptfunct with multiple arguments, returning a Tuple?
# @inline adaptfunc(adapters::Vararg{Any,N}) where N = map(adaptfunc, adapters)


"""
    adapted_call(f, af, args...)

Call the function `f` with the arguments `args...`, with both `f` (in case
`f` is a closure`) and `args...` adapted via the function `af`.

Semanically equivalent to `af(f)(map(af, args)...)`.

`af` will typically be the result of `af = adaptfunc(something_to_adapt_to)`
(see [`adapted_bcast`](@ref) for examples regarding `af`).
"""
function adapted_call end

@inline adapted_call(f::F, af::CurriedAdapt, args...) where F = af(f)(map(af, args)...)
@inline adapted_call(f::F, to::A, args...) where {F,A} = adapted_call(f, adaptfunc(to), args...)
@inline adapted_call(f::F, ::Type{Adapter}, args...) where {F,Adapter} = adapted_call(f, adaptfunc(Adapter), args...)


"""
    adapted_bcast(f, af, args...)

Broadcast function `f` over the arguments `args...`, with both `f` (in case
`f` is a closure`)` and `args...` adapted via the function `af`.

Semanically equivalent to `broadcast(af(f), map(af, args)...)`.

`af` will typically be the result of `af = adaptfunc(something_to_adapt_to)`.

For example:

```julia
⋮ = adaptfunc(Strided.StridedView)
⋰ = adaptfunc(StrideArrays.StrideArray)

adapted_bcast(⋮, f, A, B) # Use Strided to multi-thread f.(A, B)
adapted_bcast(⋰, f, A, B) # Use StrideArrays to multi-thread f.(A, B)
```

See also [`adaptfunc`](@ref).
"""
function adapted_bcast end

@inline adapted_bcast(f::F, af::CurriedAdapt, args...) where F =  broadcast(af(f), map(af, args)...)
@inline adapted_bcast(f::F, to::A, args...) where {F,A} = adapted_bcast(f, adaptfunc(to), args...)
@inline adapted_bcast(f::F, ::Type{Adapter}, args...) where {F,Adapter} = adapted_bcast(f, adaptfunc(Adapter), args...)

@inline adapted_bcast!(f::F, af::CurriedAdapt, args...) where F = broadcast!(af(f), map(af, args)...)
@inline adapted_bcast!(f::F, to::A, args...) where {F,A} = adapted_bcast!(f, adaptfunc(to), args...)
@inline adapted_bcast!(f::F, ::Type{Adapter}, args...) where {F,Adapter} = adapted_bcast!(f, adaptfunc(Adapter), args...)


"""
    struct PPTypeAdapter{T} end

Adapter to an (array) type `T` (for `Adapt.adapt_storage`) that requires
special handling. By default, `Adapt.adapt_storage(::PPTypeAdapter, obj)` will
return `obj` unchanged.

# Implementation

`PPTypeAdapter` instances should result from calls to
`ParallelProcessingTools.pp_adapter(to_something)`, they should not be
constructed by user code directly.
"""
struct PPTypeAdapter{T} end

const PPTypeAdaptFunc{T} = CurriedAdapt{PPTypeAdapter{T}}
Base.show(@nospecialize(io::IO), @nospecialize(f::PPTypeAdaptFunc{T})) where T = print(io, "adaptfunc($(nameof(T)))")
Base.show(@nospecialize(io::IO), ::MIME"text/plain", @nospecialize(f::PPTypeAdaptFunc{T})) where T = show(io, f)

@inline Adapt.adapt_storage(to::PPTypeAdapter, A::AbstractArray) = _ppt_adapt_storage(to, A)
@inline _ppt_adapt_storage(::PPTypeAdapter, A::AbstractArray) = A


@inline pp_adapter(::Type{Array}) = PPTypeAdapter{Array}()
_ppt_adapt_storage(::PPTypeAdapter{Array}, A::AbstractArray) = Array(A)


# ToDo (maybe): Add: parallel_bcast and parallel_bcast like
# parallel_bcast(::Type{Strided.StridedView}, f, args...)
# parallel_bcast(::Type{StrideArrays.StrideArray}, f, args...)
# parallel_bcast(::Type{Task}, f, args...)
# parallel_bcast(::Type{Distributed.Worker}, f, args...)
# @inline is_parallelizing_arraytype(::Type{<:AbstractArray}) = Val(false)
# is_parallelizing_arraytype(T) = throw(ArgumentError("is_parallelizing_arraytype requires an array type as argument"))
# ...


# ToDo: Add adapted_copyto! to replace parallel_copyto!?

"""
    parallel_copyto!(A, B)

Semanically equivalent to `copyto!(A, B)`, but may used multi-threading or
other parallelization techniques to speed up the operation.
"""
function parallel_copyto!(A, B) end

parallel_copyto!(A, B) = copyto!(⋮(A), ⋮(B))

parallel_copyto!(A::_CPUArrayLike, B::_NonLinIndexView) = _threads_parallel_copyto!(A, B)
parallel_copyto!(A::_NonLinIndexView, B::_CPUArrayLike) = _threads_parallel_copyto!(A, B)
parallel_copyto!(A::_NonLinIndexView, B::_NonLinIndexView) = _threads_parallel_copyto!(A, B)

function _threads_parallel_copyto!(A, B)
    idxs = eachindex(A)
    idxs == eachindex(B) || throw(ArgumentError("parallel_copyto! requires A and B to have exactly equal indices."))

    # ToDo: Tune heuristic for using multi-threading:
    if length(idxs) < 1000
        copyto!(A, B)
    else
        @inbounds Base.Threads.@threads for i in idxs
            A[i] = B[i]
        end
    end

    return A
end

function parallel_copyto!(A::StructArray{T,N}, B::StructArray{T,N}) where {T,N}
    map(parallel_copyto!, StructArrays.components(A), StructArrays.components(B))
    return A
end
