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
        Main.IJulia.stdio_bytes[] = 0 # issue #76: circumvent IJulia I/O throttling
    elseif isdefined(Main, :ESS) || isdefined(Main, :Atom)
    else
        print(io, "\u1b[K")     # clear the rest of the line
    end
end


"""
    watch_show(obj, interval::Real = 1)
    watch_show(io::IO, obj, interval::Real = 1)

Show `obj` every `interval` seconds.
"""
function watch_show end
export watch_show

function watch_show(@nospecialize(obj::Any), @nospecialize(interval::Real = 1))
    watch_show(stdout, obj, interval)
end

function watch_show(io::IO, @nospecialize(obj::Any), @nospecialize(interval::Real = 1))
    while true
        printover(io) do tmpio
            vscode_nb_mode = in_vscode_notebook()
            ioctx = IOContext(tmpio, :compact => vscode_nb_mode)
            show(ioctx,  MIME"text/plain"(), obj)
        end
        sleep(interval)
    end
end
