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
    ParallelProcessingTools.printover(f_show::Function, io::IOBuffer; nclear::Integer=0)

Runs `f_show(tmpio)` with an IO buffer, then clears the required number of
lines (at least `nclear`) on `io` (typically `stdout`) and prints the output
over them.
"""
function printover(@nospecialize(f_show), io; @nospecialize(nclear::Integer=0))
    min_n_to_clear = Int(nclear)

    vscode_nb_mode = in_vscode_notebook()

    tmpio = IOBuffer()
    f_show(tmpio)
    seekstart(tmpio)
    output_lines = readlines(tmpio)
    if vscode_nb_mode
        output_lines = [join(strip.(output_lines), " | ")]
    end

    n_lines = length(output_lines)
    n_to_clear = max(min_n_to_clear, n_lines)
    _move_cursor_up_while_clearing_lines(io, n_lines)
    for _ in Base.OneTo(n_to_clear - n_lines)
        _printover_screen(io, "")
        println(io)
    end
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
function _printover_screen(io::IO, line::AbstractString, color::Symbol = :color_normal)
    print(io, "\r")
    printstyled(io, line; color=color)
    if isdefined(Main, :IJulia)
        Main.IJulia.stdio_bytes[] = 0 # issue #76: circumvent IJulia I/O throttling
    elseif isdefined(Main, :ESS) || isdefined(Main, :Atom)
    else
        print(io, "\u1b[K")     # clear the rest of the line
    end
end





mutable struct StatusDisplay
    _output::IO
    _mime::MIME
    _objects::Vector
    _lock::ReentrantLock
    _mininterval::Float64
    _enabled::Bool
end






"""
    ParallelProcessingTools.ppt_status_display()::Real

Get the minimum interval for status/progress display updates, in seconds.

See also [`display_interval!(dt)`](@ref).
"""
function ppt_status_display()
    lock(_g_display_lock) do
        return _g_status_interval_interval[]
    end
end
export ppt_status_display


"""
    ParallelProcessingTools.status_display_interval()::Real

Get the minimum interval for status/progress display updates, in seconds.

See also [`display_interval!(dt)`](@ref).
"""
function status_display_interval()
    lock(_g_display_lock) do
        return _g_status_interval_interval[]
    end
end

"""
    ParallelProcessingTools.display_interval!(dt::Real)

Set the minimum interval for status/progress display updates, in seconds.

Returns the new value.

See also [`status_display_interval()`](@ref).
"""
function status_display_interval!(@nospecialize(dt::Real))
    @argcheck dt >= 1
    lock(_g_display_lock) do
        _g_status_interval_interval[] = dt
        return _g_status_interval_interval[]
    end
end


_g_status_display_enabled = Ref(false)

"""
    ParallelProcessingTools.status_display_enabled()::Bool

Get the minimum interval for status/progress display updates, in seconds.

See also [`display_interval!(dt)`](@ref).
"""
function status_display_enabled()
    lock(_g_display_lock) do
        return _g_status_display_enabled[]
    end
end

"""
    ParallelProcessingTools.display_interval!(dt::Real)

Set the minimum interval for status/progress display updates, in seconds.

Returns the new value.

See also [`status_display_enabled()`](@ref).
"""
function display_interval!(enable::Bool)
    lock(_g_display_lock) do
        _g_status_display_enabled[] = enable
        return _g_status_display_enabled[]
    end
end


"""
    ParallelProcessingTools.show_status(@nospecialize(io::IO), mime::MIME, obj)

Shows the status of obj. Returns `nothing`.

Defaults to `show(io, mime, obj)`.

Not primarily intended for direct use, but for specialization for different
object types. Used by []`display_status(obj)`](@ref).

See also [`show_status_compact()`](@ref).
"""
function show_status end

function show_status(io::IO, mime::MIME, @nospecialize(obj))
    show(io, mime, obj)
    return nothing
end


"""
    ParallelProcessingTools.show_status_compact(@nospecialize(io::IO), mime::MIME, obj)
    
Shows the status of obj in a compact fashion. Must only output a single line
for MIME"text/plain". Returns `nothing`.

Defaults to `show(IOContext(io, :compact => true), mime, obj)` (with newline
removal for MIME"text/plain").

Not primarily intended for direct use, but for specialization for different
object types. Used by [`display_status(obj)`](@ref).

See also [`show_status()`](@ref).
"""
function show_status_compact end

function show_status_compact(io::IO, mime::MIME, @nospecialize(obj))
    show(IOContext(io, :compact => true), mime, obj)
    return nothing
end

function show_status_compact(io::IO, mime::MIME"text/plain", @nospecialize(obj))
    tmpio = IOBuffer()
    show(IOContext(tmpio, :compact => true), mime, obj)
    seekstart(tmpio)
    output_lines = readlines(tmpio)
    output = join(strip.(output_lines), " | ")
    println(io, output)
    return nothing
end


"""
    ParallelProcessingTools.add_status!(sd::StatusDisplay, obj)
    ParallelProcessingTools.add_status!(obj)

Add obj to the list of objects to display status for and trigger a status
display update.

If no status display `sd` is provided, the default status display
`ppt_status_display()` is used.

Use [`remove_status!(obj)`](@ref) to remove obj from the status display.
"""
function add_status! end
add_status!(object) = add_status!(ppt_status_display(), object)


"""
    ParallelProcessingTools.final_status!(sd::StatusDisplay, obj)
    ParallelProcessingTools.final_status!(obj)

Add obj to the list of objects to display status for and trigger a status
display update.

If no status display `sd` is provided, the default status display
`ppt_status_display()` is used.

Use [`remove_status!(obj)`](@ref) to remove obj from the status display.
"""
function final_status! end
final_status!(object) = add_status!(ppt_status_display(), object)




const _g_default_status_display = Ref{Union{StatusDisplay,Nothing}}(nothing)
const _g_default_status_display_lock = ReentrantLock()

"""
    ppt_status_display()

Gets the default ParallelProcessingTools status display.
"""
function ppt_status_display()
    get_withlock!(() -> StatusDisplay, _g_default_status_display, _g_default_status_display_lock)
end
export ppt_status_display

"""
    ppt_status_display!(sd::StatusDisplay)

Sets the default ParallelProcessingTools status display to `sd` and returns
it.

See [`ppt_status_display()`](@ref).
"""
function ppt_status_display!(sd::StatusDisplay)
    set_withlock!(_g_default_status_display, sd, _g_default_status_display_lock)
end
export ppt_status_display!
