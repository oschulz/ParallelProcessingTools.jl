# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: split_basename_ext, tmp_filename

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

    for use_cache in [false, true]
        @testset "create_files" begin
            mktempdir() do dir
                data1 = "Hello"
                data2 = "World"

                fn1 = joinpath(dir, "targetdir", "hello.txt")
                fn2 = joinpath(dir, "targetdir", "world.txt")

                # Target directory does not exist yet:
                try
                    # Will not create missing target directory:
                    create_files(fn1, fn2, use_cache = use_cache, create_dirs = false, verbose = true) do fn1, fn2
                        write(fn1, data1); write(fn2, data2)
                    end
                    @test false # Should have thrown an exception
                catch err
                    @test err isa SystemError || err isa Base.IOError
                end

                # Test atomicity, fail in between writing files:
                @test_throws ErrorException create_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1)
                    error("Some error")
                    write(fn2, data2)
                end
                @test !isfile(fn1) && !isfile(fn2)

                # Will create:
                create_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end
                @test read(fn1, String) == data1 && read(fn2, String) == data2

                # Modify the target files:
                write(fn1, "dummy content"); write(fn2, "dummy content"); 

                # Wont't overwrite:
                create_files(fn1, fn2, use_cache = use_cache, overwrite = false, verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end
                @test read(fn1, String) != data1 && read(fn2, String) != data2

                # Will overwrite:
                create_files(fn1, fn2, use_cache = use_cache, verbose = true) do fn1, fn2
                    write(fn1, data1); write(fn2, data2)
                end
                @test read(fn1, String) == data1 && read(fn2, String) == data2
            end
        end
    end
end

ENV["JULIA_DEBUG"] = old_julia_debug; nothing
