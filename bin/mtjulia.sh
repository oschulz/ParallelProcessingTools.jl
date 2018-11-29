#!/bin/bash -e

phys_cores() {
    lscpu -p | grep -v '^#' | cut -d ',' -f 2 | sort | uniq | wc -l
}

phys_cores_node() {
    lscpu -p | grep '^[0-9]\+,[0-9]\+,[0-9]\+,0,' | cut -d ',' -f 2 | sort | uniq | wc -l
}


get_num_threads() {
    ARG="$1"
    case "${ARG}" in
        [0-9]*) echo "${ARG}" ;;
        phys_cores_node) phys_cores_node ;;
        phys_cores) phys_cores ;;
        nproc) nproc ;;
        auto)
            if [ `nproc` -le 4 ] ; then
                nproc
            else
                phys_cores_node
            fi
            ;;
        *)
            echo "ERROR: Invalid argument \"${ARG}\" for get_num_threads." >&2
            return 1
            ;;
    esac
}


NTHREADS="auto"
PRECMD=""
# while getopts j:p: opt
# do
#     case "$opt" in
#         j) NTHREADS="$OPTARG" ;;
#         p) PRECMD="$OPTARG" ;;
#     esac
# done
# shift `expr $OPTIND - 1`


NTHREADS=`get_num_threads "${NTHREADS}"`
# echo "INFO: Setting environment variables for ${NTHREADS} threads." >&2

export OMP_NUM_THREADS="${NTHREADS}"
export JULIA_NUM_THREADS="${NTHREADS}"

exec ${PRECMD} julia "$@"
