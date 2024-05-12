# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    ParallelProcessingTools.split_basename_ext(file_basename_with_ext::AbstractString)

Splits a filename (given without its directory path) into a basename without
file extension and the file extension. Returns a tuple `(basename_noext, ext)`.

Example:

```
ParallelProcessingTools.split_basename_ext("myfile.tar.gz") == ("myfile", ".tar.gz")
```
"""
function split_basename_ext(bn_ext::AbstractString)
    ext_startpos = findfirst('.', bn_ext)
    bn, ext = isnothing(ext_startpos) ? (bn_ext, "") : (bn_ext[1:ext_startpos-1], bn_ext[ext_startpos:end])
    return bn, ext
end


"""
    ParallelProcessingTools.tmp_filename(fname::AbstractString)
    ParallelProcessingTools.tmp_filename(fname::AbstractString, dir::AbstractString)

Returns a temporary filename, based on `fname`.

By default, the temporary filename is in the same directory as `fname`,
otherwise in `dir`.

Does *not* create the temporary file, only returns the filename (including
directory path).
"""
function tmp_filename end

function tmp_filename(fname::AbstractString, dir::AbstractString)
    bn_ext = basename(fname)
    bn, ext = split_basename_ext(bn_ext)
    tag = _rand_fname_tag()
    joinpath(dir, "$(bn)_$(tag)$(ext)")
end

tmp_filename(fname::AbstractString) = tmp_filename(fname, dirname(fname))

_rand_fname_tag() = String(rand(b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", 8))


const _g_default_cachedir = Ref{String}("")
const _g_default_cachedir_lock = ReentrantLock()


const _g_file_cleanup_lock = ReentrantLock()
const _g_files_to_clean_up = Set{String}()

const _g_files_autocleanup = Ref{Bool}(false)

function _add_file_to_cleanup(filename::AbstractString)
    lock(_g_file_cleanup_lock) do
        push!(_g_files_to_clean_up, filename)
        if _g_files_autocleanup[] == false
            _g_files_autocleanup[] = true
            atexit(_cleanup_files)
        end
    end
end

function _remove_file_from_cleanup(filename::AbstractString)
    lock(_g_file_cleanup_lock) do
        delete!(_g_files_to_clean_up, filename)
    end
end

function _cleanup_files()
    lock(_g_file_cleanup_lock) do
        for filename in _g_files_to_clean_up
            if isfile(filename)
                rm(filename; force=true)
            end
        end
        empty!(_g_files_to_clean_up)
    end
end



"""
    ParallelProcessingTools.default_cache_dir()::String

Returns the default cache directory, e.g. for [`write_files`](@ref) and
`read_files`(@ref).

See also [`default_cache_dir!`](@ref).
"""
function default_cache_dir()
    lock(_g_default_cachedir_lock) do
        if isempty(_g_default_cachedir[])
            cache_dir = _generate_cache_path()
            @info "Setting default cache directory to \"$cache_dir\""
            default_cache_dir!(cache_dir)
        end
        return _g_default_cachedir[]
    end
end

function _generate_cache_path()
    username_var = Sys.iswindows() ? "USERNAME" : "USER"
    tag = get(ENV, username_var, _rand_fname_tag())
    return joinpath(tempdir(), "pptjl-cache-$tag")
end


"""
    ParallelProcessingTools.default_cache_dir!(dir::AbstractString)

Sets the default cache directory to `dir` and returns it.

See also [`default_cache_dir!`](@ref).
"""
function default_cache_dir!(dir::AbstractString)
    lock(_g_default_cachedir_lock) do
        _g_default_cachedir[] = dir
        return _g_default_cachedir[]
    end
end



"""
    abstract type WriteMode

Abstract type for write modes.

May be one of the following subtypes: [`CreateNew`](@ref),
[`CreateOrIgnore`](@ref), [`CreateOrReplace`](@ref), [`CreateOrModify`](@ref),
[`ModifyExisting`](@ref).

Used by [`write_files`](@ref).
"""
abstract type WriteMode end
export WriteMode


"""
    CreateOrIgnore() isa WriteMode

Indicates that new files should be created, and that nothing should be done if
if the files already exist.

Causes an error to be thrown if only some of the files exist, to indicate an
inconsistent state.

`CreateOrIgnore()` is the recommended default when creating files in a
parallel computing context, especially if failure or timeouts might result in
re-tries. This way, if multiple workers try to create the same file(s), only
one file or consistent set of files will be created under the target
filenames.
        
See [`WriteMode`](@ref) and [`write_files`](@ref).
"""
struct CreateOrIgnore <: WriteMode end
export CreateOrIgnore

function _already_done(ftw::CreateOrIgnore, target_fnames::AbstractVector{<:String}, any_pre_existing::Bool, all_pre_existing::Bool, loglevel::LogLevel)
    if any_pre_existing
        if all_pre_existing
            @logmsg loglevel "Files $target_fnames already exist, nothing to do."
            return true
        else
            throw(ErrorException("Only some of $target_fnames exist, but not allowed to replace files"))
        end
    else
        return false
    end
end

_will_modify_files(::CreateOrIgnore, all_pre_existing::Bool) = false
_should_overwrite_if_necessary(::CreateOrIgnore) = false


"""
    CreateNew() isa WriteMode

Indicates that new files should be created and to throw and eror if the files
already exist.

See [`WriteMode`](@ref) and [`write_files`](@ref).
"""
struct CreateNew <: WriteMode end
export CreateNew

function _already_done(::CreateNew, target_fnames::AbstractVector{<:String}, any_pre_existing::Bool, all_pre_existing::Bool, loglevel::LogLevel)
    if any_pre_existing
        throw(ErrorException("Some, but not all of $target_fnames exist, but not allowed to replace files"))
    else
        return false
    end
end

_will_modify_files(::CreateNew, all_pre_existing::Bool) = false
_should_overwrite_if_necessary(::CreateNew) = false


"""
    CreateOrReplace() isa WriteMode

Indicates that new files should be created and existing files should be
replaced.

See [`WriteMode`](@ref) and [`write_files`](@ref).
"""
struct CreateOrReplace <: WriteMode end
export CreateOrReplace

function _already_done(::CreateOrReplace, target_fnames::AbstractVector{<:String}, any_pre_existing::Bool, all_pre_existing::Bool, loglevel::LogLevel)
    return false
end

_will_modify_files(::CreateOrReplace, all_pre_existing::Bool) = false
_should_overwrite_if_necessary(::CreateOrReplace) = true


"""
    CreateOrIgnore() isa WriteMode

Indicates that either new files should be created, or that existing files
should be modified.

Causes an error to be thrown if only some of the files exist already, to
indicate an inconsistent state.
        
See [`WriteMode`](@ref) and [`write_files`](@ref).
"""
struct CreateOrModify <: WriteMode end
export CreateOrModify

function _already_done(::CreateOrModify, target_fnames::AbstractVector{<:String}, any_pre_existing::Bool, all_pre_existing::Bool, loglevel::LogLevel)
    if any_pre_existing && !all_pre_existing
        throw(ErrorException("Some, but not all of $target_fnames exist, but not allowed to replace files"))
    else
        return false
    end
end

_will_modify_files(::CreateOrModify, all_pre_existing::Bool) = all_pre_existing
_should_overwrite_if_necessary(::CreateOrModify) = true


"""
    ModifyExisting() isa WriteMode

Indicates that existing files should be modified.

Causes an error to be thrown if not all of the files exist already.
        
See [`WriteMode`](@ref) and [`write_files`](@ref).
"""
struct ModifyExisting <: WriteMode end
export ModifyExisting

function _already_done(::ModifyExisting, target_fnames::AbstractVector{<:String}, any_pre_existing::Bool, all_pre_existing::Bool, loglevel::LogLevel)
    if !all_pre_existing
        throw(ErrorException("Not all of $target_fnames exist, can't modify"))
    else
        return false
    end
end

_will_modify_files(::ModifyExisting, all_pre_existing::Bool) = true
_should_overwrite_if_necessary(::ModifyExisting) = true



"""
    struct ParallelProcessingTools.FilesToWrite

Created by [`write_files`](@ref), represents a set of (temporary) files to
write to.

With `ftw::FilesToWrite`, use `collect(ftw)` or `iterate(ftw)` to access the
filenames to write to. Use `close(ftw)` or `close(ftw, true)` to close things
in good order, indicating success, and use `close(ftw, false)` or
`close(ftw, err:Exception)` to abort, indicating failure.

See [`write_files`](@ref) for example code.

If aborted or if the Julia process exits without `ftw` being closed, temporary
files are still cleaned up, unless `write_files` was used with
`delete_tmp_onerror = false`.
"""
struct FilesToWrite{M<:WriteMode}
    _mode::M
    _isopen::Ref{Bool}
    _target_fnames::Vector{String}
    _staging_fnames::Vector{String}
    _cache_fnames::Vector{String}
    _delete_tmp_onerror::Bool
    _loglevel::LogLevel
end

_writeto_filenames(ftw::FilesToWrite) = isempty(ftw._cache_fnames) ? ftw._staging_fnames : ftw._cache_fnames

Base.length(ftw::FilesToWrite) = length(_writeto_filenames(ftw))
Base.eltype(ftw::FilesToWrite) = eltype(_writeto_filenames(ftw))
Base.iterate(ftw::FilesToWrite) = iterate(_writeto_filenames(ftw))
Base.iterate(ftw::FilesToWrite, state) = iterate(_writeto_filenames(ftw), state)

Base.isopen(ftw::FilesToWrite) = ftw._isopen[]

Base.close(ftw::FilesToWrite) = _finalize_ftw(ftw)
Base.close(ftw::FilesToWrite, @nospecialize(err::Exception)) = _abort_ftw(ftw, err)
Base.close(ftw::FilesToWrite, success::Bool) = success ? _finalize_ftw(ftw) : _abort_ftw(ftw, nothing)

function _finalize_ftw(ftw::FilesToWrite)
    if ftw._isopen[]
        ftw._isopen[] = false
    else
        return nothing
    end

    mode, delete_tmp_onerror, loglevel = ftw._mode, ftw._delete_tmp_onerror, ftw._loglevel
    target_fnames, staging_fnames, cache_fnames = ftw._target_fnames, ftw._staging_fnames, ftw._cache_fnames
    use_cache = !isempty(cache_fnames)

    try
        post_write_existing = isfile.(target_fnames)
        if any(post_write_existing)
            overwrite = _should_overwrite_if_necessary(mode)
            if all(post_write_existing)
                if !overwrite
                    @logmsg loglevel "Files $target_fnames already exist, won't replace."
                    _writefiles_cleanup(ftw._cache_fnames, ftw._staging_fnames)
                    return nothing
                end
            else
                !overwrite && throw(ErrorException("Only some of $target_fnames exist but not allowed to replace files"))
            end
        end
    
        move_complete = similar(target_fnames, Bool)
        fill!(move_complete, false)

        try
            if use_cache
                _parallel_mv(cache_fnames, staging_fnames)
                foreach(_remove_file_from_cleanup, cache_fnames)
                empty!(cache_fnames)
            end

            @userfriendly_exceptions @sync for i in eachindex(staging_fnames, target_fnames)
                Threads.@spawn begin
                    staging_fn = staging_fnames[i]
                    target_fn = target_fnames[i]
                    @assert staging_fn != target_fn
                    @debug "Renaming file \"$staging_fn\" to \"$target_fn\"."
                    isfile(staging_fn) || error("Expected file \"$staging_fn\" to exist, but it doesn't.")
                    mv(staging_fn, target_fn; force=true)
                    _remove_file_from_cleanup(staging_fn)
                    isfile(target_fn) || error("Tried to rename file \"$staging_fn\" to \"$target_fn\", but \"$target_fn\" doesn't exist.")
                    move_complete[i] = true
                end
            end
            empty!(staging_fnames)

            @logmsg loglevel "Created files $target_fnames."
        catch err
            if any(move_complete) && !all(move_complete)
                to_remove = target_fnames[findall(move_complete)]
                @error "Failed to rename some of the temporary files to target files, removing $to_remove"
                for fname in to_remove
                    rm(fname; force=true)
                end
            end
            rethrow()
        end

        @assert isempty(cache_fnames)
        @assert isempty(staging_fnames)
    finally
        if delete_tmp_onerror
            _writefiles_cleanup(ftw._cache_fnames, ftw._staging_fnames)
        end
    end
end

function _abort_ftw(@nospecialize(ftw::FilesToWrite), @nospecialize(reason::Union{Exception,Nothing}))
    ftw._isopen[] = false
    if isnothing(reason)
        @debug "Aborting writing to $(ftw._target_fnames) as requested."
    else
        @debug "Aborting writing to $(ftw._target_fnames) due to exception:" reason
    end

    if ftw._delete_tmp_onerror
        _writefiles_cleanup(ftw._cache_fnames, ftw._staging_fnames)
    end
    return nothing
end

function _writefiles_cleanup(cache_fnames::AbstractVector{<:AbstractString}, staging_fnames::AbstractVector{<:AbstractString})
    lock(_g_file_cleanup_lock) do
        for cache_fn in cache_fnames
            _remove_file_from_cleanup(cache_fn)
            if isfile(cache_fn)
                @debug "Removing left-over write-cache file \"$cache_fn\"."
                rm(cache_fn; force=true)
            end
        end
        for staging_fn in staging_fnames
            _remove_file_from_cleanup(staging_fn)
            if isfile(staging_fn)
                @debug "Removing left-over write-staging file \"$staging_fn\"."
                rm(staging_fn; force=true)
            end
        end
    end
    return nothing
end



"""
    function write_files(
        [f_write,] filenames::AbstractString...;
        mode::WriteMode = CreateOrIgnore(),
        use_cache::Bool = false, cache_dir::AbstractString = default_cache_dir(),
        create_dirs::Bool = true, delete_tmp_onerror::Bool=true,
        verbose::Bool = false
    )

Writes to `filenames` in an atomic fashion, on a best-effort basis (depending
on the OS and file-system used).

`mode` determines how to handle pre-existing files, it may be
[`CreateOrIgnore()`](@ref) (default), [`CreateNew()`](@ref),
[`CreateOrReplace()`](@ref), [`CreateOrModify()`](@ref) or
[`ModifyExisting()`](@ref).

If a writing function `f_write` is given, calls
`f_create(temporary_filenames...)`. If `f_create` doesn't throw an exception,
the files `temporary_filenames` are renamed to `filenames`, otherwise
the temporary files are are either deleted (if `delete_tmp_onerror` is `true)
or left in place (e.g. for debugging purposes).

Set `ENV["JULIA_DEBUG"] = "ParallelProcessingTools"` to see a log of all
intermediate steps.

For example:

```julia
write_files("foo.txt", "bar.txt", use_cache = true) do tmp_foo, tmp_bar
    write(tmp_foo, "Hello")
    write(tmp_bar, "World")
end
```

`write_files(f_write, filenames...)` returns either `filenames`, if the
files were (re-)written or `nothing` if there was nothing to do (depending
on `mode`).

If no writing funcion `f_write` is given then, `write_files` returns an object
of type [`FilesToWrite`](@ref) that holds the temporary filenames. Closing it
will, like above, either rename temporary files to `filenames` or remove them.
So

```julia
ftw = write_files("foo.txt", "bar.txt")
if !isnothing(ftw)
    try
        foo, bar = ftw
        write(foo, "Hello")
        write(bar, "World")
        close(ftw)
    catch err
        close(ftw, err)
        rethrow()
    end
end
```

is equivalent to the example using `write_files(f_write, ...)`above.

When modifying files, `write_files` first copies existing files `filenames` to
`temporary_filenames` and otherwise behaves as described above.

If `use_cache` is `true`, the `temporary_filenames` are located in
`cache_dir` and then atomically moved to `filenames`, otherwise they located
next to `filenames` (so in the same directories).

If `create_dirs` is `true`, target and cache directory paths are
created if necessary.

If `verbose` is `true`, uses log-level `Logging.Info` to log file creation,
otherwise `Logging.Debug`.

On Linux you can set `use_cache = true` and `cache_dir = "/dev/shm"` to use
the default Linux RAM disk as an intermediate directory.

See also [`read_files`](@ref) and
[`ParallelProcessingTools.default_cache_dir`](@ref).
"""
function write_files end
export write_files

function write_files(@nospecialize(f_write), @nospecialize(filenames::AbstractString...); kwargs...)
    if isempty(filenames)
        return nothing
    else
        ftw = write_files(filenames...; kwargs...)
        if isnothing(ftw)
            return nothing
        else
            try
                f_write(ftw...)
                close(ftw)
                return filenames
            catch err
                close(ftw, err)
                rethrow()
            end
        end
    end
end

function write_files(
    @nospecialize(filenames::AbstractString...);
    mode::WriteMode = CreateOrIgnore(),
    use_cache::Bool = false, @nospecialize(cache_dirname::AbstractString = default_cache_dir()),
    create_dirs::Bool = true, delete_tmp_onerror::Bool=true,
    verbose::Bool = false
)
    isempty(filenames) && return nothing

    loglevel = verbose ? Info : Debug

    cache_dir = String(cache_dirname) # Fix type
    target_fnames = String[filenames...] # Fix type
    staging_fnames = String[]
    cache_fnames = String[]

    pre_existing = isfile.(target_fnames)
    any_pre_existing = any(pre_existing)
    all_pre_existing = all(pre_existing)

    _already_done(mode, target_fnames, any_pre_existing, all_pre_existing, loglevel) && return nothing

    try
        dirs = dirname.(target_fnames)
        if create_dirs
            for dir in dirs
                if !isdir(dir) && !isempty(dir)
                    mkpath(dir)
                    @logmsg loglevel "Created output directory $dir."
                end
            end

            if use_cache && !isdir(cache_dir) && !isempty(cache_dir) && create_dirs
                mkpath(cache_dir)
                @logmsg loglevel "Created write-cache directory $cache_dir."
            end
        end

        if use_cache
            append!(cache_fnames, tmp_filename.(target_fnames, Ref(cache_dir)))
            @assert !any(isfile, cache_fnames)
        end

        append!(staging_fnames, tmp_filename.(target_fnames))
        @assert !any(isfile, staging_fnames)

        ftw = FilesToWrite(mode, Ref(true), target_fnames, staging_fnames, cache_fnames, delete_tmp_onerror, loglevel)

        if delete_tmp_onerror
            foreach(_add_file_to_cleanup, staging_fnames)
            foreach(_add_file_to_cleanup, cache_fnames)
        end

        writeto_fnames = _writeto_filenames(ftw)
        if _will_modify_files(mode, all_pre_existing)
            @debug "Copying files $target_fnames to intermediate files $writeto_fnames."
            read_files(target_fnames...; use_cache=false) do readfrom_fnames...
                _parallel_cp(readfrom_fnames, writeto_fnames)
            end
            @debug "Modifying intermediate files $writeto_fnames."
        else
            @debug "Creating intermediate files $writeto_fnames."
        end

        return ftw
    catch
        if delete_tmp_onerror
            _writefiles_cleanup(cache_fnames, staging_fnames)
        end
        rethrow()
    end

    return nothing
end



"""
    struct ParallelProcessingTools.FilesToRead

Created by [`read_files`](@ref), represents a set of (temporary) files to
read from.

With `ftr::FilesToRead`, use `collect(ftr)` or `iterate(ftr)` to access the
filenames to read from. Use `close(ftr)` or `close(ftr, true)` to close
things in good order, indicating success, and use `close(ftr, false)` or
`close(ftr, err:Exception)` to abort, indicating failure.

See [`read_files`](@ref) for example code.

If aborted or if the Julia process exits without `ftr` being closed, temporary
files are still cleaned up, unless `read_files` was used with
`delete_tmp_onerror = false`.
"""
struct FilesToRead
    _isopen::Ref{Bool}
    _source_fnames::Vector{String}
    _cache_fnames::Vector{String}
    _delete_tmp_onerror::Bool
    _loglevel::LogLevel
end

Base.isopen(ftr::FilesToRead) = ftr._isopen[]

function _readfrom_filenames(ftr::FilesToRead)
    if isopen(ftr)
        isempty(ftr._cache_fnames) ? ftr._source_fnames : ftr._cache_fnames
    else
        throw(InvalidStateException("FilesToRead is closed.", :closed))
    end
end

Base.length(ftr::FilesToRead) = length(_readfrom_filenames(ftr))
Base.eltype(ftr::FilesToRead) = eltype(_readfrom_filenames(ftr))
Base.iterate(ftr::FilesToRead) = iterate(_readfrom_filenames(ftr))
Base.iterate(ftr::FilesToRead, state) = iterate(_readfrom_filenames(ftr), state)

Base.close(ftr::FilesToRead) = close(ftr, true)
function Base.close(ftr::FilesToRead, @nospecialize(reason::Union{Bool,Exception}))
    ftr._isopen[] = false

    if reason == true
        # @debug "Reading from to $(ftr._source_fnames) was indicated to have succeeded."
    elseif reason == false
        @debug "Reading from to $(ftr._source_fnames) was indicated to have failed."
    else
        @debug "Aborted reading from $(ftr._source_fnames) due to exception:" reason
    end

    if reason == true || ftr._delete_tmp_onerror
        _readfiles_cleanup(ftr._cache_fnames)
    end
    empty!(ftr._cache_fnames)
    empty!(ftr._source_fnames)
    return nothing
end

function _readfiles_cleanup(cache_fnames::AbstractVector{<:AbstractString})
    lock(_g_file_cleanup_lock) do
        for cache_fn in cache_fnames
            _remove_file_from_cleanup(cache_fn)
            if isfile(cache_fn)
                @debug "Removing left-over read-cache file \"$cache_fn\"."
                rm(cache_fn; force=true)
            end
        end
    end
end


"""
    function read_files(
        [f_read, ], filenames::AbstractString...;
        use_cache::Bool = true, cache_dir::AbstractString = default_cache_dir(),
        create_cachedir::Bool = true, delete_tmp_onerror::Bool=true,
        verbose::Bool = false
    )

Reads `filenames` in an atomic fashion (i.e. only if all `filenames` exist)
on a best-effort basis (depending on the OS and file-system used).

If a reading function `f_read` is given, calls `f_read(filenames...)`. The
return value of `f_read` is passed through.

If `use_cache` is `true`, then the files are first copied to the
cache directory `cache_dir` under temporary names, and then read via
`f_read(temporary_filenames...)`. The temporary files are
deleted after `f_read` exits (except if an exception is thrown during reading
and `delete_tmp_onerror` is set to `false`).

Set `ENV["JULIA_DEBUG"] = "ParallelProcessingTools"` to see a log of all
intermediate steps.

For example:

```julia
write("foo.txt", "Hello"); write("bar.txt", "World")

result = read_files("foo.txt", "bar.txt", use_cache = true) do foo, bar
    read(foo, String) * " " * read(bar, String)
end
```

If no reading funcion `f_read` is given, then `read_files` returns an object
of type [`FilesToRead`](@ref) that holds the temporary filenames. Closing it
will clean up temporary files, like described above. So


```julia
ftr = read_files("foo.txt", "bar.txt"; use_cache = true)
result = try
    foo, bar = collect(ftr)
    data_read = read(foo, String) * " " * read(bar, String)
    close(ftr)
    data_read
catch err
    close(ftr, err)
    rethrow()
end
```

is equivalent to the example using `read_files(f_read, ...)`above.

If `create_cachedir` is `true`, then `cache_dir` will be created if it doesn't
exist yet.

If `verbose` is `true`, uses log-level `Logging.Info` to log file reading,
otherwise `Logging.Debug`.

On Linux you can set `use_cache = true` and `cache_dir = "/dev/shm"` to use
the default Linux RAM disk as an intermediate directory.

See also [`write_files`](@ref) and
[`ParallelProcessingTools.default_cache_dir`](@ref).
"""
function read_files end
export read_files

function read_files(@nospecialize(f_read), @nospecialize(filenames::AbstractString...); kwargs...)
    ftr = read_files(filenames...; kwargs...)
    try
        readfrom_fnames = collect(ftr)
        result = f_read(readfrom_fnames...)
        close(ftr)
        return result
    catch err
        close(ftr, err)
        rethrow()
    end
end

function read_files(
    @nospecialize(filenames::AbstractString...);
    use_cache::Bool = true, cache_dir::AbstractString = default_cache_dir(),
    create_cachedir::Bool = true, delete_tmp_onerror::Bool=true,
    verbose::Bool = false
)
    loglevel = verbose ? Info : Debug

    source_fnames = String[filenames...] # Fix type
    cache_fnames = String[]

    @logmsg loglevel "Preparing to read files $source_fnames."

    input_exists = isfile.(source_fnames)
    if !all(input_exists)
        missing_inputs = source_fnames[findall(!, input_exists)]
        throw(ErrorException("Missing input files $(missing_inputs)."))
    end

    try
        if use_cache
            if !isdir(cache_dir) && !isempty(cache_dir) && create_cachedir
                mkpath(cache_dir)
                @logmsg loglevel "Created read-cache directory $cache_dir."
            end

            append!(cache_fnames, tmp_filename.(source_fnames, Ref(cache_dir)))
            @assert !any(isfile, cache_fnames)

            foreach(_add_file_to_cleanup, cache_fnames)
            _parallel_cp(source_fnames, cache_fnames)
        end
        
        return FilesToRead(Ref(true), source_fnames, cache_fnames, delete_tmp_onerror, loglevel)
    catch
        if delete_tmp_onerror
            _readfiles_cleanup(cache_fnames)
        end
        rethrow()
    end
end


function _parallel_mv(source_fnames, target_fnames)
    @userfriendly_exceptions @sync for (source_fn, target_fn) in zip(source_fnames, target_fnames)
        Threads.@spawn begin
            @assert source_fn != target_fn
            @debug "Moving file \"$source_fn\" to \"$target_fn\"."
            isfile(source_fn) || error("Expected file \"$source_fn\" to exist, but it doesn't.")
            mv(source_fn, target_fn)
            isfile(target_fn) || error("Expected file \"$target_fn\" to exist, but it doesn't.")
        end
    end
end


function _parallel_cp(source_fnames, target_fnames)
    @userfriendly_exceptions @sync for (target_fn, source_fn) in zip(target_fnames, source_fnames)
        Threads.@spawn begin
            @assert target_fn != source_fn
            @debug "Copying file \"$source_fn\" to \"$target_fn\"."
            cp(source_fn, target_fn)
            isfile(target_fn) || error("Tried to copy file \"$source_fn\" to \"$target_fn\", but \"$target_fn\" did't exist afterwards.")
        end
    end
end
