#!/bin/bash


# To kick off a job, make sure you first
#
# - place any needed support files in support/some/path/
# - have a job description in command/some/path.json including
#    {"command":["executable", "arg1", "arg2", ...]
#    ,"timeout":10              # wall-clock seconds (optional, default 10)
#    ,"network":true            # optional, default false
#    ,"image":"my_special_docker_image_name" # optional
#    }
#
# - make a working directory with submitted files in runme/some/path/mst3k/
#
# - *after* the above, touch queue/some#path#mst3k



#################### Default values (overridable) ####################
DIR=/opt/sandbox
DEF_TIMEOUT=10
DEF_IMAGE=sandbox_machine
MAX_TIMEOUT=900
######################### End default values #########################

if [ "$USER" != "root" ]
then
	echo "Requires root priviledges; attempting to become root"
	SCRIPT="$(readlink -f "$0")"
	echo '>>>>' sudo bash "$SCRIPT"
	sudo "/bin/bash" "$SCRIPT"
	exit $?
fi

mkdir -p $DIR -m 755 # only needed once, but put here so it always works



# Single copy only!
_LOCKFILE="$DIR/daemon.lock"
_LOCKFD=99
_lock()    { flock -$1 $_LOCKFD; }
_unlock()  { _lock u; _lock xn && rm -f $_LOCKFILE; }
eval "exec $_LOCKFD>\"$_LOCKFILE\""; trap _unlock EXIT;
_lock xn || exit 1


SUB=$DIR/runme
CMD=$DIR/command
LOG=$DIR/log
SUP=$DIR/support
Q=$DIR/queue

mkdir -p $SUB -m 777
mkdir -p $CMD -m 777
mkdir -p $LOG $LOG/.bad -m 777
mkdir -p $SUP -m 777
mkdir -p $Q -m 777


# recursive mkdir with chown/chmod to mirror another directory
#
#  rmkdir /path/to/any/kind/of/existing/tree \
#         /path/to/new/tree
#
# creates /path/to/new/tree/of/existing/tree
function rmkdir {
	# echo rmkd "$@"
	old=$(readlink -m "$1")
	if [ ! -d "$old" ]; then return 1; fi
	new=$(readlink -m "$2")
	while [ -n "$new" ]
	do
		old="$(echo "/$old" | cut -d/ -f3-)"
		new="$(echo "/$new" | cut -d/ -f3-)"
	done
	make="$old"
	old=$(readlink -m "$1")
	old="${old%/$make}"
	new=$(readlink -m "$2")
	# echo make $new/$make
	while [ -n "$make" ]
	do
		bit="${make%%/*}"
		old="$old/$bit"
		new="$new/$bit"
		make="$(echo "/$make" | cut -d/ -f3-)"
		mkdir -p "$new"
		chown --reference="$old" "$new"
		chmod --reference="$old" "$new"
	done
}

# makes $1's owner == its directory's owner and sets mode to 644
# given two args, copy's permissions from second to first
function ownfix {
	if [ "$#" = "2" ]
	then
		chown --reference="$2" "$1"
		chmod --reference="$2" "$1"
	else
		chown --reference="$(dirname "$1")" "$1"
		chmod 644 "$1"
	fi
}

function handle {
	
	log="$LOG/.bad/$req"
	d2="$(readlink -m $SUB/"$(echo "$req" | tr '#' '/')")"
	tail="${d2#$SUB/}"
	
	# verify path name
	if [ "$tail" = "$d2" ]; then 
		echo "bad $Q entry" > "$log"; 
		ownfix "$log" "$Q/$req"; 
		rm "$Q/$req"
		return 1; 
	fi
	
	# find submission directory
	if [ ! -d "$SUB/$tail" ]; then 
		echo "no directory $SUB/$tail" > "$log"; 
		ownfix "$log" "$Q/$req"; 
		rm "$Q/$req"
		return 2; 
	fi

	# remove queue entry (no longer needed for permission copying)
	rm "$Q/$req"
	
	# make proper log location
	rmkdir $SUB/$tail $LOG
	log="$LOG/$tail/$(date +%Y%m%d-%H%M%S.%N)"
	
	cloc="$CMD/$tail"
	sloc="$SUP/$tail"
	
	# find the command
	while [ -n "${cloc#$CMD}" ] && [ ! -e "$cloc.json" ]
	do
		cloc="$(dirname "$cloc")"
    done
 	while [ -n "${sloc#$CMD}" ] && [ ! -d "$sloc" ]
 	do
		sloc="$(dirname "$sloc")"
	done
	if [ ! -e "$cloc.json" ]; then echo "No command file found" >> "$log.status"; ownfix "$log.status"; return 3; fi
	
	# read JSON string or array into bash array
	mapfile -t cmd < <(jq  '.command | ((arrays|.[])//strings)' -r "$cloc.json")
	if [ "${#cmd[@]}" -lt 1 ]; then echo "No command found in $cloc.json" >> "$log.status"; ownfix "$log.status"; return 4; fi
    
    # Read timeout with default
    tout=$(jq ".timeout // $DEF_TIMEOUT" "$cloc.json")
    [ "$tout" -gt $MAX_TIMEOUT ] && tout=$MAX_TIMEOUT
    # Read image with default
    image=$(jq ".image // \"$DEF_IMAGE\"" -r "$cloc.json")
    
    if docker inspect $image -f " " &>/dev/null; then echo -n '' >/dev/null;
    else echo "No image $image found in docker" >> "$log.status"; ownfix "$log.status"; return 5; 
    fi
    
    # Read network with default of false, and reformat for docker
    net=$(jq '.network // false' "$cloc.json")
    [ "$net" = "true" ] && net=default || net=none
    
    # copy support classes to submission directory
    if [ -d $sloc ]; then cp -f -p -r $sloc/* $SUB/$tail/; fi

	echo "Running with $tout-second timeout" >> "$log.status"; ownfix "$log.status";

    pid=$(docker run \
        --env="HOME=/usercode" \
        --detach \
        --volume="$SUB/$tail":/usercode \
        --workdir=/usercode \
        --user nobody \
        --network=$net \
        --memory=2g \
        --pids-limit=512 \
        --ulimit nproc=1024:2048 \
        "$image" \
        "${cmd[@]}")
    end=$(timeout $tout docker wait "$pid")
    if [ -z "$end" ];
    then
        docker kill "$pid" &>/dev/null # echos PID killed
        docker logs "$pid" 1>"$log.out" 2>"$log.err"
        docker rm "$pid" &>/dev/null # echos PID removed
        echo "timeout after $tout seconds (wall-clock)" >> "$log.status"
    else
        docker logs "$pid" 1>"$log.out" 2>"$log.err"
        docker rm "$pid" &>/dev/null # echos PID removed
        echo "exit code $end" >> "$log.status"
    fi

    if false # disable removing support files (may have changed)
    then
        if [ -d $sloc ]
        then for sup in $sloc/*
            do rm -r "$sup"
            done
        fi
    fi
	
	# make log files accessible to submitting user
	[ -f "$log.status" ] && ownfix "$log.status";
	[ -f "$log.out" ] && ownfix "$log.out";
	[ -f "$log.err" ] && ownfix "$log.err";
}

again=1
while [ $again -gt 0 ]
do
	again=0
	ls $Q | while read req
	do
		handle "$req"
		let again+=1
	done
done

# race condition: if queue added to between above loop and inotifywait, never handled

inotifywait --monitor --format="%f" -e modify -e close_write -e moved_to $Q | while read req
do
	handle "$req"
done
