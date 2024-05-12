# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: split_basename_ext, tmp_filename, default_cache_dir, default_cache_dir!

old_julia_debug = get(ENV, "JULIA_DEBUG", "")
ENV["JULIA_DEBUG"] = old_julia_debug * ",ParallelProcessingTools"

@testset "fileio" begin
    @testset "split_basename_ext" begin
        @test @inferred(split_basename_ext("foo_bar baz.tar.gz")) == ("foo_bar baz", ".tar.gz")
    end

    @testset "tmp_filename" begin
        dir = joinpath("foo", "bar")
        tmpdir = joinpath(tempdir(), "somedir")
        bn = "test.tar.gz"
        fn = joinpath(dir, bn)

        @test @inferred(tmp_filename(fn)) isa AbstractString
        let tmpfn = @inferred tmp_filename(fn)
            @test dirname(tmpfn) == dir
            tmp_bn, tmp_ex = split_basename_ext(basename(tmpfn))
            @test startswith(tmp_bn, "test_")
            @test tmp_ex == ".tar.gz"
        end

        @test @inferred(tmp_filename(fn, tmpdir)) isa AbstractString
        let tmpfn = @inferred tmp_filename(fn, tmpdir)
            @test dirname(tmpfn) == tmpdir
            tmp_bn, tmp_ex = split_basename_ext(basename(tmpfn))
            @test startswith(tmp_bn, "test_")
            @test tmp_ex == ".tar.gz"
        end
    end

    @testset "default_cache_dir" begin
        @test @inferred(default_cache_dir()) isa String
        orig_cache_dir = default_cache_dir()
        @test mkpath(orig_cache_dir) == orig_cache_dir
        dummy_cache_dir = joinpath("some", "tmp", "dir")
        @test @inferred(default_cache_dir!(dummy_cache_dir)) == dummy_cache_dir
        @test default_cache_dir() == dummy_cache_dir
        @test default_cache_dir!(orig_cache_dir) == orig_cache_dir
        @test default_cache_dir() == orig_cache_dir
    end


    for use_cache in (true, false), throw_dummy_error in (true, false), test_abort_write in (true, false)
        @testset "write_files cache=$use_cache, error=$throw_dummy_error, abort=$test_abort_write" begin
            mktempdir() do dir
                data1 = "Hello"
                data2 = "World"

                fn1 = joinpath(dir, "targetdir", "hello.txt")
                fn2 = joinpath(dir, "targetdir", "world.txt")

                @test write_files() isa Nothing
                ftw = write_files("foo.txt", "bar.txt", mode = CreateOrIgnore(), use_cache = use_cache)
                @test ftw isa ParallelProcessingTools.FilesToWrite{CreateOrIgnore}
                tmp_foo, tmp_bar = ftw
                try
                    write.([tmp_foo, tmp_bar], ["Hello", "World"])
                    @test in(tmp_foo, ParallelProcessingTools._g_files_to_clean_up)
                    @test in(tmp_bar, ParallelProcessingTools._g_files_to_clean_up)
                    throw_dummy_error && error("Some error")
                    test_abort_write ? close(ftw, false) : close(ftw)
                catch err
                    close(ftw, err)
                end
                if !(throw_dummy_error || test_abort_write)
                    @test all(isfile, ["foo.txt", "bar.txt"])
                    @test read.(["foo.txt", "bar.txt"], String) == ["Hello", "World"]
                    @test write_files("foo.txt", "bar.txt") isa Nothing
                    rm.(["foo.txt", "bar.txt"])
                end
                @test !in(tmp_foo, ParallelProcessingTools._g_files_to_clean_up)
                @test !in(tmp_bar, ParallelProcessingTools._g_files_to_clean_up)
                @test !any(isfile, ftw._cache_fnames)
                @test !any(isfile, ftw._staging_fnames)
                @test !any(f -> f in ParallelProcessingTools._g_files_to_clean_up, ftw._cache_fnames)
                @test !any(f -> f in ParallelProcessingTools._g_files_to_clean_up, ftw._staging_fnames)
            end
        end
    end

    for use_cache in [false, true]
        @testset "write_files f_write $(use_cache ? "with" : "without") cache" begin
            mktempdir() do dir
                data1 = "Hello"
                data2 = "World"

                fn1 = joinpath(dir, "targetdir", "hello.txt")
                fn2 = joinpath(dir, "targetdir", "world.txt")

                # Target directory does not exist yet:
                try
                    # Will not create missing target directory:
                    write_files(fn1, fn2, use_cache = use_cache, create_dirs = false, verbose = true) do fn1, fn2
                        write(fn1, data1); write(fn2, data2)
                    end
                    @test false # Should have thrown an exception
                catch err
                    @test err isa SystemError || err isa Base.IOError
                end

                # Test atomicity, fail in between writing files:
                @test_throws ErrorException write_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1)
                    error("Some error")
                    write(fn2, data2)
                end
                @test !isfile(fn1) && !isfile(fn2)

                # Will create:
                @test write_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end == (fn1, fn2)
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Remove files:
                rm.([fn1, fn2])

                # Will create:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateOrIgnore(), verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end == (fn1, fn2)
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Remove files:
                rm.([fn1, fn2])

                # Will create:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateNew(), verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end == (fn1, fn2)
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Files already exixst:
                @test_throws ErrorException write_files(fn1, fn2, use_cache = use_cache, mode = CreateNew(), verbose = true) do fn1, fn2
                    write(fn1, "modified"); write(fn2, "content")
                end

                # Modify the target files:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateOrModify(), verbose = true) do fn1, fn2
                    write(fn1, "modified"); write(fn2, "content")
                end == (fn1, fn2)
                @test read(fn1, String) == "modified" && read(fn2, String) == "content"

                # Remove files:
                rm.([fn1, fn2])

                # Files don't exist yet:
                @test_throws ErrorException write_files(fn1, fn2, use_cache = use_cache, mode = ModifyExisting(), verbose = true) do fn1, fn2
                    write(fn1, "modified"); write(fn2, "content")
                end

                # Will create:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateOrModify(), verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end == (fn1, fn2)
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Modify the target files:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = ModifyExisting(), verbose = true) do fn1, fn2
                    write(fn1, "modified"); write(fn2, "content")
                end == (fn1, fn2)
                @test read(fn1, String) == "modified" && read(fn2, String) == "content"

                # Wont't overwrite:
                @test write_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end isa Nothing
                @test read(fn1, String) != data1 && read(fn2, String) != data2

                # Wont't overwrite:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateOrIgnore(), verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end isa Nothing
                @test read(fn1, String) != data1 && read(fn2, String) != data2

                # Will overwrite:
                @test write_files(fn1, fn2, use_cache = use_cache, mode = CreateOrReplace(), verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end == (fn1, fn2)
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Remove files:
                rm.([fn1, fn2])
           end
        end
    end


    for use_cache in (true, false), throw_dummy_error in (true, false), test_abort_read in (true, false)
        @testset "read_files cache=$use_cache, error=$throw_dummy_error, abort=$test_abort_read" begin
            mktempdir() do dir
                data1 = "Hello"
                data2 = "World"

                fn1 = joinpath(dir, "targetdir", "hello.txt")
                fn2 = joinpath(dir, "targetdir", "world.txt")

                mkpath(dirname(fn1)); mkpath(dirname(fn2))
                write(fn1, data1); write(fn2, data2)

                ftr = read_files(fn1, fn2, use_cache = use_cache)
                @test ftr isa ParallelProcessingTools.FilesToRead
                tmp_foo, tmp_bar = ftr
                result = try
                    if use_cache
                        @test in(tmp_foo, ParallelProcessingTools._g_files_to_clean_up)
                        @test in(tmp_bar, ParallelProcessingTools._g_files_to_clean_up)
                    end
                    throw_dummy_error && error("Some error")
                    if test_abort_read
                        close(ftr, false)
                    else
                        read_data = read.([tmp_foo, tmp_bar], String)
                        close(ftr)
                        read_data
                    end
                catch err
                    close(ftr, err)
                end
                if !(throw_dummy_error || test_abort_read)
                    @test result == ["Hello", "World"]
                end
                @test !in(tmp_foo, ParallelProcessingTools._g_files_to_clean_up)
                @test !in(tmp_bar, ParallelProcessingTools._g_files_to_clean_up)
                @test !any(isfile, ftr._cache_fnames)
                @test !any(f -> f in ParallelProcessingTools._g_files_to_clean_up, ftr._cache_fnames)
            end
        end
    end

    for use_cache in [false, true]
        @testset "read_files $(use_cache ? "with" : "without") cache" begin
            mktempdir() do dir
                data1 = "Hello"
                data2 = "World"

                fn1 = joinpath(dir, "targetdir", "hello.txt")
                fn2 = joinpath(dir, "targetdir", "world.txt")

                mkpath(dirname(fn1)); mkpath(dirname(fn2))
                write(fn1, data1); write(fn2, data2)

                @test_throws ErrorException read_files(
                    (fn1, fn2) -> (read(fn1, String), read(fn2, String)),
                    fn1, "nosuchfile.txt", use_cache = use_cache, verbose = true
                )

                @test @inferred(read_files(
                    (fn1, fn2) -> (read(fn1, String), read(fn2, String)),
                    fn1, fn2, use_cache = use_cache, verbose = true
                )) == (data1, data2)
            end
        end
    end
end

ENV["JULIA_DEBUG"] = old_julia_debug; nothing
