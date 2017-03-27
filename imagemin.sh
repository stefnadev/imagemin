#!/bin/bash

defaultUrl="http://localhost:8082"
CHECK_NOOP=.noop
concurrency=2
threshold=1
optCheckFileBase=.imagemin.list
OPT_CHECK_DIR="${OPT_CHECK_DIR:-/var/www/vhosts}"
optCheckFile="$OPT_CHECK_DIR/$optCheckFileBase"

BASE_DIR=$(dirname $0)

. ${BASE_DIR}/funcs.sh

usage() {
	echo -e "Usage: $0: PATH [MTIME] [URL] [CONCURRENCY] [THRESHOLD]\n" >&2
	echo -e "\tPATH:        Path to image files" >&2
	echo -e "\tMTIME:       Optional: Find files modified less than MTIME days ago" >&2
	echo -e "\tURL:         Optional: Send request to URL (default=$defaultUrl)" >&2
	echo -e "\tCONCURRENCY: Optional: How many concurrent processes (default=$concurrency)" >&2
	echo -e "\tTHRESHOLD:   Optional: Set mininum optimization threshold (default=$threshold)" >&2
	echo  >&2
	if [ "$1" != "" ]; then
		exit $1
	else
		exit 1
	fi
}

if [ "$1" == "-h" -o "$1" == "--help" ]; then
	usage
fi

if [ $# -lt 1 ]; then
	error "Missing arguments"
fi

if [ "$2" != "" ]; then
	re='^[0-9]+$'
	if ! [[ $2 =~ $re ]]; then
		error "MTIME must be a number" "'$2' is not a number " 4
	fi
fi

# Read parameters
IMAGEPATH="$1"
MTIME="$2"
if [ "$MTIME" == "0" ]; then
	MTIME=""
fi
URL=${defaultUrl}
if [[ "$3" =~ https? ]]; then
	URL="$3"
fi

if [ "$4" != "" ]; then
	concurrency=$4
fi

if [ "$5" != "" ]; then
	threshold="$5"
	if [[ ! "$threshold" =~ ^[0-9]{1,2}$ ]]; then
	 	error "Threshold must be a number between 1 and 99"
	fi
fi

if [ ! -f "$optCheckFile" ]; then
	( touch "$optCheckFile" && chmod 666 "$optCheckFile" ) > /dev/null 2>&1
fi
if [ ! -w "$optCheckFile" ]; then
	error "Could not write to '$optCheckFile'"
fi

ping "$URL"

findCommand() {
	# Process all file extensions
	ext=""
	if [ $# -gt 1 ]; then
		for i in $@; do
			t="-iname *.$i"
			if [ "$ext" ]; then
				ext="$ext -o $t"
			else
				ext="$t"
			fi
		done
		ext=" ( $ext ) "
	else
		ext="-iname *.$1"
	fi
	# Minimum of 128bytes
	# And must be a file (no symlinks allowed)
	ret="-type f -size +128c $ext"

	# Add mtime parameter if in use
	if [ "$MTIME" ]; then
		ret="$ret -mtime -$MTIME"
	fi

	echo "$ret"
}
declare -A checkedDirs=()
shouldRunDir() {
	local file="${1%/}"
	local base="${2%/}"
	local dir="$(dirname "$file")"
	local ret

	[ ${checkedDirs[$dir]+_} ] && {
		test ${checkedDirs[$dir]} == 't'
		return $?
	}

	if [ ! -f "$dir/$CHECK_NOOP" ] ; then
		ret='t'
	else
		ret='f'
	fi

	if [ ${ret} == 'f' -o "$dir" == "$base" ]; then
		checkedDirs[$dir]=${ret}
		test ${ret} == 't'
		return $?
	fi

	shouldRunDir "$dir" "$base"
	if [ $? -eq 0 ]; then
		ret='t'
	else
		ret='f'
	fi
	checkedDirs[$dir]=${ret}
	test ${ret} == 't'
	return $?
}
shouldRun() {
	local file="${1%/}"
	local base="${2%/}"
	if ! shouldRunDir "$file" "$base" ; then
		# Directory should not be processed
		return 1
	fi
	local lastOptTime=$(egrep "$file$" "$optCheckFile"|tail -n 1)
	if [ "$lastOptTime" == "" ]; then
		# Not yet optimized
		return 0
	fi
	lastOptTime=${lastOptTime/%\ */}
	mtime=$(stat -c %Y "$file")
	if [ ${mtime} -gt ${lastOptTime} ]; then
		# file has changed since last optimization
		return 0
	fi
	return 1
}
optimizeDir() {
	local findCmd=$(findCommand $@)

	local time=$(date +%s)

	local commandsFile=/tmp/_imagemin_cmds_$$
	> ${commandsFile}
	local script="$BASE_DIR/imagemin_one.sh"
	if [ "$threshold" != "" ]; then
		script="$script -t $threshold"
	fi

	# we need to use while read to optimize files with space in filename
	find "$IMAGEPATH" ${findCmd} | while read -r FILE; do
		if shouldRun "$FILE" "$IMAGEPATH"; then
			echo "$script '$URL' '$(escape "$FILE")'" >> ${commandsFile}
			echo "$time $FILE" >> "$optCheckFile"
		else
			echo "NOOP: $FILE"
		fi
	done

	local count=$(wc -l ${commandsFile}|awk '{print $1}')
	echo "OK All files gathered. Now running $count commands with concurrency of $concurrency (PID=$$):"
	cat ${commandsFile} | xargs -I CMD --max-procs=${concurrency} bash -c CMD
	local ltime=$(date +%s)
	local totalTime="$(( $ltime - $time ))"
	echo "Optimization done in $totalTime sec"
	rm ${commandsFile}
}

# for debugging
#set -x

# no globbing so we won't accidentally match some files while running find
set -f

optimizeDir png jpg jpeg
