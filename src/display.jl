# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

const _g_unicode_vbars = ['\u2800', '\u2581', '▂', '▃', '▄', '▅', '▆', '▇', '█']

const _g_unicode_state = (
    green = '🟢',
    yellow = '🟡',
    orange = '🟠',
    red = '🔴'
)

const _g_unicode_occupancy = (
    sleeping = '💤',
    working = '🔧',
    onfire = '🔥',
    overloaded = '🤯',
    waiting = '⏳',
    blocked = '🚫',
    finished = '🏁',
    failed = '❌',
    succeeded = '✅',
    unknown = '❓'
)


"""
    ParallelProcessingTools.in_vscode_notebook():Bool

Test if running within a Visual Studio Code notebook.
"""
in_vscode_notebook() = haskey(ENV, "VSCODE_CWD")


"""
    ParallelProcessingTools.printover(f_show::Function, io::IOBuffer)

Runs `f_show(tmpio)` with an IO buffer, then clears the required number of
lines on `io` (typically `stdout`) and prints the output over them.
"""
function printover(f_show, io)
    vscode_nb_mode = in_vscode_notebook()

    tmpio = IOBuffer()
    f_show(tmpio)
    seekstart(tmpio)
    output_lines = readlines(tmpio)
    if vscode_nb_mode
        output_lines = [join(strip.(output_lines), " | ")]
    end

    n_lines = length(output_lines)
    _move_cursor_up_while_clearing_lines(io, n_lines)
    for l in output_lines
        _printover_screen(io, l)
        println(io)
    end
end

# Taken from ProgressMeter.jl:
function _move_cursor_up_while_clearing_lines(io, numlinesup)
    if numlinesup > 0 && (isdefined(Main, :IJulia) && Main.IJulia.inited)
        Main.IJulia.clear_output(true)
    else
        for _ in 1:numlinesup
            print(io, "\r\u1b[K\u1b[A")
        end
    end
end

# Taken from ProgressMeter.jl:
function _printover_screen(io::IO, s::AbstractString, color::Symbol = :color_normal)
    print(io, "\r")
    printstyled(io, s; color=color)
    if isdefined(Main, :IJulia)
        # issue #76: circumvent IJulia I/O throttling
        if pkgversion(Main.IJulia) < v"1.30"
            Main.IJulia.stdio_bytes[] = 0
        else
            Main.IJulia.reset_stdio_count()
        end
    elseif isdefined(Main, :ESS) || isdefined(Main, :Atom)
    else
        print(io, "\u1b[K")     # clear the rest of the line
    end
end
