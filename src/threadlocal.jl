# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    abstract type AbstractThreadLocal{T} end

Abstract type for thread-local values of type `T`.

The value for the current thread is accessed via
`getindex(::AbstractThreadLocal)` and `setindex(::AbstractThreadLocal, x).

To access both regular and thread-local values in a unified manner, use
the function [`getlocalvalue`](@ref).

To get the all values across all threads, use the function
[`getallvalues`](@ref).

Default implementation is [`ThreadLocal`](@ref).
"""
abstract type AbstractThreadLocal{T} end
export AbstractThreadLocal


"""
    getlocalvalue(x::Any) = x
    getlocalvalue(x::ThreadLocal) = x[]

Access plain values and thread-local values in a unified fashion.
"""
function getlocalvalue end
export getlocalvalue


"""
    getallvalues(v::AbstractThreadLocal{T})::AbstractVector{T}

Access the all values (one for each thread) of a thread-local value as a
vector. Can only be called in single-threaded code sections.
"""
function getallvalues end
export getallvalues



function _protect_from_resize(V::Vector)
    reshape(V, length(V), 1)
    V
end


"""
    ThreadLocal{T} <: AbstractThreadLocal{T}

Represents a thread-local value. See [`AbstractThreadLocal`](@ref) for
the API.

Constructors:

```julia
ThreadLocal{T}() where {T}
ThreadLocal(value::T) where {T}
ThreadLocal{T}(f::Base.Callable) where {T}
```

Examples:

```julia
tlvalue = ThreadLocal(0)
@onthreads allthreads() tlvalue[] = Base.Threads.threadid()
getallvalues(tlvalue) == allthreads()
```

```julia
rand_value_on_each_thread = ThreadLocal{Float64}(rand)
all(x -> 0 < x < 1, getallvalues(rand_value_on_each_thread))
```
"""
struct ThreadLocal{T} <: AbstractThreadLocal{T}
    value::Vector{T}

    ThreadLocal{T}(::UndefInitializer) where {T} =
        new{T}(_protect_from_resize(Vector{T}(undef, nthreads())))

    ThreadLocal{T}(value::T) where {T} =
        new{T}(_protect_from_resize([deepcopy(value) for i in 1:nthreads()]))
end

export ThreadLocal

ThreadLocal{T}() where {T} = ThreadLocal{T}(T)

ThreadLocal(value::T) where {T} = ThreadLocal{T}(value)


@inline Base.getindex(x::ThreadLocal) = x.value[threadid()]

@inline Base.setindex!(x::ThreadLocal, y) = x.value[threadid()] = y


Base.eltype(x::Type{<:ThreadLocal{T}}) where {T} = @isdefined(T) ? T : Any


@inline Base.get(x::ThreadLocal) = x[]

@inline Base.get(default::Base.Callable, x::ThreadLocal{T}) where {T} = isassigned(x) ? x[] : convert(T, default())

@inline Base.get(x::ThreadLocal, default) = get(() -> default, x)

function Base.get!(default::Base.Callable, x::ThreadLocal{T}) where {T}
    if isassigned(x)
        x[]
    else
        x[] = convert(T, default())
    end
end

Base.get!(x::ThreadLocal, default) = get!(() -> default, x)


@inline getlocalvalue(x) = x
@inline getlocalvalue(x::ThreadLocal) = x[]


Base.isassigned(x::ThreadLocal) = isassigned(x.value, threadid())

function getallvalues(x::ThreadLocal)
    @static if VERSION >= v"1.3.0-alpha.0"
        x.value
    else
        if !Base.Threads.in_threaded_loop[]
            x.value
        else
            throw(InvalidStateException("Can not access thread local values across threads in multi-threaded code sections"))
        end
    end
end
