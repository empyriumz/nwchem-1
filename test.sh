#!/bin/bash

# Set the environment
. /etc/profile

###########################################################################
# start the SOS aggregator
###########################################################################

export SOS_CMD_PORT=22500
export SOS_WORK=`pwd`
export SOS_EVPATH_MEETUP=`pwd`
#export SOS_IN_MEMORY_DATABASE=1
#export SOS_EXPORT_DB_AT_EXIT=verbose 
export SOS_DB_DISABLED=1
export TAU_SOS_CACHE_DEPTH=100
export SOS_PUB_CACHE_DEPTH=100
export TAU_VERBOSE=1

# clean-up previous run
rm -f log.* core* conf dataspaces.conf

SERVER=/Install/dataspaces-1.7.2/bin/dataspaces_server

WRITEPROC=1
STAGINGPROC=1
READPROC=1
let "PROCALL=WRITEPROC+READPROC"

# Prepare config file for DataSpaces
echo "## Config file for DataSpaces
ndim = 2
dims = 100,100
max_versions = 10
#max_readers =" $READPROC "
#lock_type = 2
" > dataspaces.conf

# Run DataSpaces
echo "-- Start DataSpaces server "$SERVER" on $STAGINGPROC PEs, -s$STAGINGPROC -c$PROCALL"
$SERVER -s$STAGINGPROC -c$PROCALL >& log.server &

## Give some time for the servers to load and startup
sleep 1s
while [ ! -f conf ]; do
    echo "-- File conf is not yet available from server. Sleep more"
    sleep 1s
done
sleep 3s  # wait server to fill up the conf file

## Export the main server config to the environment
while read line; do
    export set "${line}"
done < conf

echo "-- DataSpaces IDs: P2TNID = $P2TNID   P2TPID = $P2TPID"

# Start STAGE_READ
echo "-- Start GENARRAY on $READPROC PEs"
python3 ./adios_read_mpi.py DATASPACES "verbose=3;check_read_status=0" >& log.reader &

# The ADIOS extraction script has to be launched on the same node as 
# one of the SOS aggregators, so the "extract" script is used to launch
# both from Slurm (using --gres-network didn't seem to work)

sos_cmd="/Install/sosflow/bin/sosd -l 0 -a 1 -w ${SOS_WORK}"
./extract.sh ${sos_cmd} -k 0 -r aggregator >& sosd.out &
#${sos_cmd} -k 0 -r aggregator >& sosd.out &

# Wait for that to startup
while [ ! -f ${SOS_WORK}/sosd.00000.key ] ; do
    echo "Waiting for ${SOS_WORK}/sosd.00000.key..."
    sleep 1
done

###########################################################################
# Launch the application
###########################################################################

# if the programs are instrumented with TAU, at the end of phases TAU
# will write data to SOS.  If not, we could have the data be written periodically.
# To use periodic output (instead of iteration boundaries), enable these variables
# (enabling these variables will disable the writing of data at the end of phases)
export TAU_SOS_PERIODIC=1
export TAU_SOS_PERIOD=1000000 # once per second

# Tell TAU where to find the SOS plugin.  This was built by TAU, if TAU was
# configured with -sos=/path/to/sos/installation
export TAU_PLUGINS=libTAU-sos-plugin.so
export TAU_PLUGINS_PATH=/Install/tau2-2018-10-04/x86_64/lib/shared-papi-mpi-pthread-pdt-sos-adios
# To reduce the amount of data sent from TAU to SOS, use a filter file:
export TAU_SOS_SELECTION_FILE=/Codar/nwchem-1/sos_filter.txt
# Tell TAU to send a full event trace to SOS:
export TAU_SOS_TRACING=1
# The shutdown delay only matters when TAU spawns the listeners.
#export TAU_SOS_SHUTDOWN_DELAY_SECONDS=10
# Tell TAU how to launch SOS listener daemons
#export SOS_FORK_COMMAND="${sos_cmd} -k @LISTENER_RANK@ -r listener"
# This is the first set of listeners after the aggregator
#export SOS_LISTENER_RANK_OFFSET=1
#export SOS_APP_RANKS_PER_NODE=4

export TAU_PROFILE_FORMAT=merged
export TAU_PROFILE_PREFIX=nwchem

. /etc/profile

cd QA/tests/ethanol

sed -i 's/coord 0/coord 1/' ethanol_md.nw
sed -i 's/scoor 0/scoor 1/' ethanol_md.nw

mpirun -n 2 ../../../bin/LINUX64/nwchem ethanol_md.nw

