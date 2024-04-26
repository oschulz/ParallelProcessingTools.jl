# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    ParallelProcessingTools.tmp_filename(fname::AbstractString)

Returns a temporary filename, based on `fname`, in the same directory.

Does *not* create the temporary file.
"""
function tmp_filename(fname::AbstractString)
    d, fn, ext = _split_dir_fn_ext(fname)
    tag = _rand_fname_tag()
    joinpath(d, "$(fn)_$(tag)$(ext)")
end    

function _split_dir_fn_ext(fname::AbstractString)
    d = dirname(fname)
    f = basename(fname)
    ext_startpos = findfirst('.', f)
    fn, ext = isnothing(ext_startpos) ? (f, "") : (f[1:ext_startpos-1], f[ext_startpos:end])
    return d, fn, ext
end

_rand_fname_tag() = String(rand(b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", 8))


"""
    function create_files(
        body, filenames::AbstractString...;
        create_dirs::Bool = true, overwrite::Bool = true, delete_on_error::Bool=true
    )

Creates `filenames` in an atomic fashion.

Creates temporary files in the same directories as `filenames`, then
calls `body(temporary_filenames...)`. If `body` returns successfully,
the files `temporary_filenames` are renamed to `filenames`. If `body` throws
an exception, the temporary files are either deleted (if `delete_on_error` is
`true`) or left in place (e.g. for debugging purposes).

If `create_dirs` is `true`, directories are created if necessary.

If all of files already exist and `overwrite` is `false`, takes no action
(or, if the file is created by other code running in parallel, while `body` is
running, does not overwrite it).

Throws an error if only some of the files exist and `overwrite` is `false`.

Returns `nothing`.

Example:

```julia
create_files("foo.txt", "bar.txt") do foo, bar
    write(foo, "Hello")
    write(bar, "World")
end
```
"""
function create_files(
    body, filenames::AbstractString...;
    create_dirs::Bool = true, overwrite::Bool = true, delete_on_error::Bool=true
)
    tmp_filenames = String[]
    completed_filenames = String[]

    pre_existing = isfile.(filenames)
    if any(pre_existing)
        if all(pre_existing)
            if !overwrite
                @info "Files $filenames already exist, nothing to do."
                return nothing
            end
        else
            !overwrite && throw(ErrorException("Only some of $filenames exist but not allowed to overwrite"))
        end
    end

    dirs = dirname.(filenames)
    for dir in dirs
        if !isdir(dir) && create_dirs
            mkpath(dir)
            @info "Created directory $dir."
        end
    end

    try
        for fname in filenames
            tmp_fname = tmp_filename(fname)
            @assert !isfile(tmp_fname)
            push!(tmp_filenames, tmp_fname)
        end

        body(tmp_filenames...)

        post_body_existing = isfile.(filenames)
        if any(post_body_existing)
            if all(post_body_existing)
                if !overwrite
                    @info "Files $filenames already exist, won't replace."
                    return nothing
                end
            else
                !overwrite && throw(ErrorException("Only some of $filenames exist but not allowed to replace files"))
            end
        end
   
        try
            for (tmp_fname, fname) in zip(tmp_filenames, filenames)
                mv(tmp_fname, fname; force=true)
                @assert isfile(fname)
                push!(completed_filenames, fname)
            end
            @info "Successfully created files $filenames."
        catch
            if !isempty(completed_filenames)
                @error "Failed to rename some temporary files to final filenames, removing $completed_filenames"
                for fname in completed_filenames
                    rm(fname; force=true)
                end
            end
            rethrow()
        end

        @assert all(fn -> !isfile(fn), tmp_filenames)
    finally
        if delete_on_error
            for tmp_fname in tmp_filenames
                isfile(tmp_fname) && rm(tmp_fname; force=true);
            end
        end
    end

    return nothing
end
export create_files
