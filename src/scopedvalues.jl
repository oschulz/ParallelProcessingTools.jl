# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

function _get_withlock!(f_default, default_ref::Ref{Union{T,Nothing}}, lockable) where T
    lock(lockable)
    try
        value = default_ref[]
        if isnothing(value)
            new_value::T = f_default()
            default_ref[] = new_value
            return new_value
        else
            return value::T
        end
    finally
        unlock(lockable)
    end
end

function _set_withlock!(default_ref::Ref[T], value, lockable) where T
    lock(lockable)
    try
        default_ref[] = value
        return value
    finally
        unlock(lockable)
    end
end


struct _ScopedValueWithDynamicDefault{T,F}
    ctor::F
    lockable::ReentrantLock
    default_ref::Ref{Union{T,Nothing}}
    scoped::ScopedValue{T}
end

function _ScopedValueWithDynamicDefault{T}(ctor::F) where {T,F}
    _ScopedValueWithDynamicDefault(ctor, ReentrantLock(), Ref{Union{T,Nothing}}(nothing), ScopedValue{T}())
end

function _get_current(svd::_ScopedValueWithDynamicDefault{T}) where T
    v = ScopedValues.get(svd.scoped)
    if isnothing(v)
        return _get_withlock!(svd.ctor, svd.default_ref, svd.lockable)::T
    else
        return v::T
    end
end

function _set_default!(svd::_ScopedValueWithDynamicDefault{T}, value::T) where T
    _set_withlock!(svd.default_ref, value, svd.lockable)
end
