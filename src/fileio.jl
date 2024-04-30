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

"""
    ParallelProcessingTools.default_cache_dir()::String

Returns the default cache directory, e.g. for [`create_files`](@ref) and
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
    function create_files(
        f_write, filenames::AbstractString...;
        overwrite::Bool = true,
        use_cache::Bool = false, cache_dir::AbstractString = default_cache_dir(),
        create_dirs::Bool = true, delete_tmp_onerror::Bool=true,
        verbose::Bool = false
    )

Creates `filenames` in an atomic fashion via a user-provided function
`f_write`. Returns `nothing`.

Using temporary filenames, calls `f_write(temporary_filenames...)`. If
`f_write` doesn't throw an exception, the files `temporary_filenames` are
renamed to `filenames`. If `f_write` throws an exception, the temporary files
are either deleted (if `delete_tmp_onerror` is `true`) or left in place (e.g. for
debugging purposes).

If `create_dirs` is `true`, the `temporary_filenames` are created in
`cache_dir` and then atomically moved to `filenames`, otherwise, they are
created next to `filenames` (in the same directories).

If `create_dirs` is `true`, directories are created if necessary.

If all of `filenames` already exist and `overwrite` is `false`, takes no
action (or, on case the files are created by other code running in parallel,
while `f_write` is running, does not replace them).

If `verbose` is `true`, uses log-level `Logging.Info` to log file creation,
otherwise `Logging.Debug`.

Throws an error if only some of the files exist and `overwrite` is `false`.

Returns `nothing`.

Example:

```julia
create_files("foo.txt", "bar.txt", use_cache = true) do foo, bar
    write(foo, "Hello")
    write(bar, "World")
end
```

Set `ENV["JULIA_DEBUG"] = "ParallelProcessingTools"` to see a log of all
intermediate steps.

On Linux you can set `use_cache = true` and `cache_dir = "/dev/shm"` to use
the default Linux RAM disk as an intermediate directory.
"""
function create_files(
    @nospecialize(f_write), @nospecialize(filenames::AbstractString...);
    overwrite::Bool = true,
    use_cache::Bool = false, cache_dir::AbstractString = default_cache_dir(),
    create_dirs::Bool = true, delete_tmp_onerror::Bool=true,
    verbose::Bool = false
)
    loglevel = verbose ? Info : Debug

    target_fnames = String[filenames...] # Fix type
    staging_fnames = String[]
    cache_fnames = String[]
    move_complete = similar(target_fnames, Bool)
    fill!(move_complete, false)

    pre_existing = isfile.(target_fnames)
    if any(pre_existing)
        if all(pre_existing)
            if !overwrite
                @logmsg loglevel "Files $target_fnames already exist, nothing to do."
                return nothing
            end
        else
            !overwrite && throw(ErrorException("Only some of $target_fnames exist but not allowed to overwrite"))
        end
    end

    dirs = dirname.(target_fnames)
    if create_dirs
        for dir in dirs
            if !isdir(dir) && create_dirs
                mkpath(dir)
                @logmsg loglevel "Created output directory $dir."
            end
        end

        if use_cache && !isdir(cache_dir)
            mkpath(cache_dir)
            @logmsg loglevel "Created write-cache directory $cache_dir."
        end
    end

    try
        if use_cache
            append!(cache_fnames, tmp_filename.(target_fnames, Ref(cache_dir)))
            @assert !any(isfile, cache_fnames)
        end

        append!(staging_fnames, tmp_filename.(target_fnames))
        @assert !any(isfile, staging_fnames)

        writeto_fnames = use_cache ? cache_fnames : staging_fnames
        @debug "Creating intermediate files $writeto_fnames."
        f_write(writeto_fnames...)

        post_f_write_existing = isfile.(target_fnames)
        if any(post_f_write_existing)
            if all(post_f_write_existing)
                if !overwrite
                    @logmsg loglevel "Files $target_fnames already exist, won't replace."
                    return nothing
                end
            else
                !overwrite && throw(ErrorException("Only some of $target_fnames exist but not allowed to replace files"))
            end
        end

        try
            if use_cache
                @userfriendly_exceptions @sync for (cache_fn, staging_fn) in zip(cache_fnames, staging_fnames)
                    Threads.@spawn begin
                        @assert cache_fn != staging_fn
                        @debug "Moving file \"$cache_fn\" to \"$staging_fn\"."
                        isfile(cache_fn) || error("Expected file \"$cache_fn\" to exist, but it doesn't.")
                        mv(cache_fn, staging_fn)
                    end
                end
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
                    isfile(target_fn) || error("Tried to rename file \"$staging_fn\" to \"$target_fn\", but \"$target_fn\" doesn't exist.")
                    move_complete[i] = true
                end
            end
            empty!(staging_fnames)

            @logmsg loglevel "Created files $target_fnames."
        catch
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
            for cache_fn in cache_fnames
                if isfile(cache_fn)
                    @debug "Removing left-over write-cache file \"$cache_fn\"."
                    rm(cache_fn; force=true)
                end
            end
            for staging_fn in staging_fnames
                if isfile(staging_fn)
                    @debug "Removing left-over write-staging file \"$staging_fn\"."
                    rm(staging_fn; force=true)
                end
            end
        end
    end

    return nothing
end
export create_files


"""
    function read_files(
        f_read, filenames::AbstractString...;
        use_cache::Bool = true, cache_dir::AbstractString = default_cache_dir(),
        create_cachedir::Bool = true, delete_tmp_onerror::Bool=true,
        verbose::Bool = false
    )

Reads `filenames` in an atomic fashion (i.e. only if all `filenames` exist)
via a user-provided function `f_read`. The returns value of `f_read` is
passed through.

If `use_cache` is `true`, then the files are first copied to the
temporary directory `cache_dir` under temporary names, and
`f_read(temporary_filenames...)` is called. The temporary files are deleted
afterwards.

If `create_cachedir` is `true`, then `cache_dir` will be created if it doesn't
exist yet. If `delete_tmp_onerror` is true, then temporary files are
deleted even if `f_write` throws an exception.

If `verbose` is `true`, uses log-level `Logging.Info` to log file reading,
otherwise `Logging.Debug`.

```julia
write("foo.txt", "Hello"); write("bar.txt", "World")

read_files("foo.txt", "bar.txt", use_cache = true) do foo, bar
    read(foo, String) * " " * read(bar, String)
end
```

Set `ENV["JULIA_DEBUG"] = "ParallelProcessingTools"` to see a log of all
intermediate steps.

On Linux you can set `use_cache = true` and `cache_dir = "/dev/shm"` to use
the default Linux RAM disk as an intermediate directory.
"""
function read_files(
    @nospecialize(f_read), @nospecialize(filenames::AbstractString...);
    use_cache::Bool = true, cache_dir::AbstractString = default_cache_dir(),
    create_cachedir::Bool = true, delete_tmp_onerror::Bool=true,
    verbose::Bool = false
)
    loglevel = verbose ? Info : Debug

    source_fnames = String[filenames...] # Fix type
    cache_fnames = String[]

    input_exists = isfile.(source_fnames)
    if !all(input_exists)
        missing_inputs = source_fnames[findall(!, input_exists)]
        throw(ErrorException("Missing input files $(missing_inputs)."))
    end

    try
        if use_cache
            if !isdir(cache_dir) && create_cachedir
                mkpath(cache_dir)
                @logmsg loglevel "Created read-cache directory $cache_dir."
            end

            append!(cache_fnames, tmp_filename.(source_fnames, Ref(cache_dir)))
            @assert !any(isfile, cache_fnames)

            @userfriendly_exceptions @sync for (cache_fn, source_fn) in zip(cache_fnames, source_fnames)
                Threads.@spawn begin
                    @assert cache_fn != source_fn
                    @debug "Copying file \"$source_fn\" to \"$cache_fn\"."
                    cp(source_fn, cache_fn)
                    isfile(cache_fn) || error("Tried to copy file \"$source_fn\" to \"$cache_fn\", but \"$cache_fn\" doesn't exist.")
                end
            end
        end

        readfrom_fnames = use_cache ? cache_fnames : source_fnames

        @debug "Reading $(use_cache ? "cached " : "")files $readfrom_fnames."
        result = f_read(readfrom_fnames...)
        @logmsg loglevel "Read files $source_fnames."

        @userfriendly_exceptions @sync for cache_fn in cache_fnames
            Threads.@spawn rm(cache_fn; force=true);
        end
        return result
    finally
        if delete_tmp_onerror
            for cache_fn in cache_fnames
                if isfile(cache_fn)
                    @debug "Removing left-over read-cache file \"$cache_fn\"."
                    rm(cache_fn; force=true)
                end
            end
        end
    end
end
export read_files
