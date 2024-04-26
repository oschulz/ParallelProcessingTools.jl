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


"""
    function create_files(
        f_write, filenames::AbstractString...;
        create_dirs::Bool = true, overwrite::Bool = true, delete_on_error::Bool=true,
        use_cache::Bool = false, cache_dir::AbstractString = tempdir(),
        verbose::Bool = true
    )

Creates `filenames` in an atomic fashion via a user-provided function
`f_write`. Returns `nothing`.

Using temporary filenames, calls `f_write(temporary_filenames...)`. If
`f_write` doesn't throw an exception, the files `temporary_filenames` are
renamed to `filenames`. If `f_write` throws an exception, the temporary files
are either deleted (if `delete_on_error` is `true`) or left in place (e.g. for
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
    create_dirs::Bool = true, overwrite::Bool = true, delete_on_error::Bool=true,
    use_cache::Bool = false, cache_dir::AbstractString = tempdir(),
    verbose::Bool = true
)
    loglevel = verbose ? Info : Debug

    target_fnames = String[filenames...] # Fix type
    staging_fnames = String[]
    writeto_fnames = String[]
    completed_fnames = String[]

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
                @logmsg loglevel "Created directory $dir."
            end
        end

        if use_cache && !isdir(cache_dir)
            mkpath(cache_dir)
            @logmsg loglevel "Created cache directory $cache_dir."
        end
    end

    try
        staging_fnames = tmp_filename.(target_fnames)
        @assert !any(isfile, staging_fnames)

        writeto_fnames = use_cache ? tmp_filename.(target_fnames, Ref(cache_dir)) : staging_fnames
        @assert !any(isfile, writeto_fnames)

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
                for (writeto_fn, staging_fn) in zip(writeto_fnames, staging_fnames)
                    @assert writeto_fn != staging_fn
                    @debug "Moving file \"$writeto_fn\" to \"$staging_fn\"."
                    isfile(writeto_fn) || error("Expected file \"$writeto_fn\" to exist, but it doesn't.")
                    mv(writeto_fn, staging_fn; force=true)
                    isfile(staging_fn) || error("Tried to move file \"$writeto_fn\" to \"$staging_fn\", but \"$staging_fn\" doesn't exist.")
                end
            end
            for (staging_fn, target_fn) in zip(staging_fnames, target_fnames)
                @assert staging_fn != target_fn
                @debug "Renaming file \"$staging_fn\" to \"$target_fn\"."
                isfile(staging_fn) || error("Expected file \"$staging_fn\" to exist, but it doesn't.")
                mv(staging_fn, target_fn; force=true)
                isfile(target_fn) || error("Tried to rename file \"$staging_fn\" to \"$target_fn\", but \"$target_fn\" doesn't exist.")
                push!(completed_fnames, target_fn)
            end
            @logmsg loglevel "Created files $target_fnames."
        catch
            if !isempty(completed_fnames)
                @error "Failed to rename some temporary files to final filenames, removing $completed_fnames"
                for fname in completed_fnames
                    rm(fname; force=true)
                end
            end
            rethrow()
        end

        @assert all(fn -> !isfile(fn), staging_fnames)
    finally
        if delete_on_error
            for writeto_fn in writeto_fnames
                isfile(writeto_fn) && rm(writeto_fn; force=true);
            end
            for staging_fn in staging_fnames
                isfile(staging_fn) && rm(staging_fn; force=true);
            end
        end
    end

    return nothing
end
export create_files
