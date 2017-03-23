#!/bin/bash

PROG=$0
STOPFILE=".noImageMin"
concurrency=

. $(dirname $0)/funcs.sh

usage() {
	echo "Usage: ${PROG} [opts] url mtime dir... " >&2
	echo -e "\turl to the stimgops server " >&2
	echo -e "\tmtime 0 to skip mtime, else this is used in the find commands " >&2
	echo >&2
	echo -e "\tOptions:" >&2
	echo -e "\t\t-c <n>: concurrency param sent to imagemin.sh" >&2
	echo >&2
	exit 1
}

dir=$(dirname ${PROG})
script="$dir/imagemin.sh"
if [ ! -f ${script} ]; then
	error "Could not find script" "$script"
fi

if [ "$1" == '--help' -o "$1" == '-h' ]; then
	usage
fi

if [ "$1" == '-c' ]; then
	concurrency=$2
	if [[ ! "$concurrency" =~ ^[1-9]$ ]]; then
	 	error "Concurrency must be a number between 1 and 9"
	fi
	shift
	shift
fi

if [ $# -lt 1 ]; then
	error "Missing arguments"
fi

url=$1
shift

if [[ ! "$url" =~ ^https?:// ]]; then
	error "'$url' does not look like a valid url"
fi

mtime=${1//[^0-9]/}
shift

if [ $# -lt 1 ]; then
	error "No directories given"
fi

ping "$url"

extraOpts=""
if [ "$concurrency" != "" ]; then
	extraOpts=" concurrency=$concurrency"
fi

echo "Starting optimizations at $(date -uR) - url: $url $extraOpts"

if [ "$mtime" == "" -o "$mtime" == "0" ]; then
	yellow "Disabling mtime"
	mtime=""
else
	yellow "mtime will be used as "
	green "-mtime -$mtime"
	yellow " in the find commands"
fi
echo

for i in $@; do
	if [ ! -e "$i" ]; then
		warn "'$i' not found\n"
	else
		p=$(realpath "$i")
		ok=1
		if [ -d ${p} ]; then
			if [ -e "${p}/${STOPFILE}" ]; then
				warn "Skipping $p because of a STOP file\n"
				ok=0
			fi
		fi
		if [ ${ok} -eq 1 ]; then
			echo "Optimizing $(green ${p}) ..."
			"${script}" "${p}" "$mtime" "${url}" "$concurrency"
		fi
	fi
done

echo "Optimizations done at $(date -uR)"
echo "----------------------------------"
echo
