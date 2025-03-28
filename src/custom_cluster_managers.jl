# This code is a modified version of ClusterManagers.ElasticManager, both
# original code and modifications are licensed under the MIT License (MIT):
# https://github.com/JuliaParallel/ClusterManagers.jl/blob/master/LICENSE.md

# Modifications are planned to be upstreamed, once tested in the field.

module CustomClusterManagers

# ==================================================================
import Distributed
import Sockets
import Pkg

using Distributed: launch, manage, kill, init_worker, connect
# ==================================================================


# The master process listens on a well-known port
# Launched workers connect to the master and redirect their STDOUTs to the same
# Workers can join and leave the cluster on demand.

export ElasticManager, elastic_worker

const HDR_COOKIE_LEN = Distributed.HDR_COOKIE_LEN

struct ElasticManager <: Distributed.ClusterManager
    active::Dict{Int, Distributed.WorkerConfig}        # active workers
    pending::Channel{Sockets.TCPSocket}          # to be added workers
    terminated::Set{Int}             # terminated worker ids
    topology::Symbol
    sockname
    manage_callback
    printing_kwargs

    function ElasticManager(;
        addr=IPv4("127.0.0.1"), port=9009, cookie=nothing,
        topology=:all_to_all, manage_callback=elastic_no_op_callback, printing_kwargs=()
    )
        Distributed.init_multi()
        cookie !== nothing && Distributed.cluster_cookie(cookie)

        # Automatically check for the IP address of the local machine
        if addr == :auto
            try
                addr = Sockets.getipaddr(Sockets.IPv4)
            catch
                error("Failed to automatically get host's IP address. Please specify `addr=` explicitly.")
            end
        end
        
        l_sock = Distributed.listen(addr, port)

        lman = new(Dict{Int, Distributed.WorkerConfig}(), Channel{Sockets.TCPSocket}(typemax(Int)), Set{Int}(), topology, Sockets.getsockname(l_sock), manage_callback, printing_kwargs)

        @async begin
            while true
                let s = Sockets.accept(l_sock)
                    @async process_worker_conn(lman, s)
                end
            end
        end

        @async process_pending_connections(lman)

        lman
    end
end

ElasticManager(port) = ElasticManager(;port=port)
ElasticManager(addr, port) = ElasticManager(;addr=addr, port=port)
ElasticManager(addr, port, cookie) = ElasticManager(;addr=addr, port=port, cookie=cookie)

elastic_no_op_callback(::ElasticManager, ::Integer, ::Symbol) = nothing

function process_worker_conn(mgr::ElasticManager, s::Sockets.TCPSocket)
    @debug "ElasticManager got new worker connection"
    # Socket is the worker's STDOUT
    wc = Distributed.WorkerConfig()
    wc.io = s

    # Validate cookie
    cookie = read(s, HDR_COOKIE_LEN)
    if length(cookie) < HDR_COOKIE_LEN
        error("Cookie read failed. Connection closed by peer.")
    end
    self_cookie = Distributed.cluster_cookie()
    for i in 1:HDR_COOKIE_LEN
        if UInt8(self_cookie[i]) != cookie[i]
            println(i, " ", self_cookie[i], " ", cookie[i])
            error("Invalid cookie sent by remote worker.")
        end
    end

    put!(mgr.pending, s)
end

function process_pending_connections(mgr::ElasticManager)
    while true
        wait(mgr.pending)
        try
            Distributed.addprocs(mgr; topology=mgr.topology)
        catch e
            showerror(stderr, e)
            Base.show_backtrace(stderr, Base.catch_backtrace())
        end
    end
end

function Distributed.launch(mgr::ElasticManager, params::Dict, launched::Array, c::Condition)
    # The workers have already been started.
    while isready(mgr.pending)
        @debug "ElasticManager.launch new worker"
        wc=Distributed.WorkerConfig()
        wc.io = take!(mgr.pending)
        push!(launched, wc)
    end

    notify(c)
end

function Distributed.manage(mgr::ElasticManager, id::Integer, config::Distributed.WorkerConfig, op::Symbol)
    if op == :register
        @debug "ElasticManager registering process id $id"
        mgr.active[id] = config
        mgr.manage_callback(mgr, id, op)
    elseif  op == :deregister
        @debug "ElasticManager deregistering process id $id"
        mgr.manage_callback(mgr, id, op)
        delete!(mgr.active, id)
        push!(mgr.terminated, id)
    end
end

function Base.show(io::IO, mgr::ElasticManager)
    iob = IOBuffer()

    println(iob, "ElasticManager:")
    print(iob, "  Active workers : [ ")
    for id in sort(collect(keys(mgr.active)))
        print(iob, id, ",")
    end
    seek(iob, position(iob)-1)
    println(iob, "]")

    println(iob, "  Number of workers to be added  : ", Base.n_avail(mgr.pending))

    print(iob, "  Terminated workers : [ ")
    for id in sort(collect(mgr.terminated))
        print(iob, id, ",")
    end
    seek(iob, position(iob)-1)
    println(iob, "]")

    println(iob, "  Worker connect command : ")
    print(iob, "    ", get_connect_cmd(mgr; mgr.printing_kwargs...))
    
    print(io, String(take!(iob)))
end

# Does not return. If executing from a REPL try
# @async elastic_worker(.....)
# addr, port that a ElasticManager on the master processes is listening on.
function elastic_worker(
    cookie::AbstractString, addr::AbstractString="127.0.0.1", port::Integer = 9009;
    stdout_to_master::Bool = true,
    Base.@nospecialize(env::AbstractVector = [],)
)
    @debug "ElasticManager.elastic_worker(cookie, $addr, $port; stdout_to_master=$stdout_to_master, env=$env)"
    for (k, v) in env
        ENV[k] = v
    end

    c = connect(addr, port)
    write(c, rpad(cookie, HDR_COOKIE_LEN)[1:HDR_COOKIE_LEN])
    stdout_to_master && redirect_stdout(c)
    Distributed.start_worker(c, cookie)
end


end # module CustomClusterManagers
