#!/bin/bash

PROG=$0
STOPFILE=".noImageMin"
concurrency=
BASE_DIR=$(dirname ${PROG})
. ${BASE_DIR}/funcs.sh

usage() {
	echo "Usage: ${PROG} [opts] url mtime dir... " >&2
	echo -e "\turl to the stimgops server " >&2
	echo -e "\tmtime 0 to skip mtime, else this is used in the find commands " >&2
	echo >&2
	echo -e "\tOptions:" >&2
	echo -e "\t\t-c <n>: concurrency param sent to imagemin.sh" >&2
	echo -e "\t\t-t <n>: threshold param sent to imagemin.sh" >&2
	echo >&2
	exit 1
}

script="$BASE_DIR/imagemin.sh"
if [ ! -f ${script} ]; then
	error "Could not find script" "$script"
fi

if [ "$1" == '--help' -o "$1" == '-h' ]; then
	usage
fi

optNum=1
optTaken=0
for opt; do
	if [ "$opt" == '-c' ]; then
		let valueNum=$optNum+1
		concurrency=${!valueNum}
		if [[ ! "$concurrency" =~ ^[1-9]$ ]]; then
			error "Concurrency must be a number between 1 and 9"
		fi
		let optTaken=$optTaken+2
	fi
	if [ "$opt" == '-t' ]; then
		let valueNum=$optNum+1
		threshold=${!valueNum}
		if [[ ! "$threshold" =~ ^[0-9]{1,2}$ ]]; then
			error "Threshold must be a number between 1 and 99"
		fi
		let optTaken=$optTaken+2
	fi
	let optNum=$optNum+1
done
if [ ${optTaken} -gt 0 ]; then
	shift ${optTaken}
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
	extraOpts="$extraOpts concurrency=$concurrency"
fi
if [ "$threshold" != "" ]; then
	extraOpts="$extraOpts threshold=$threshold"
fi

echo "Starting optimizations at $(date -uR) - url: $url$extraOpts"

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
			"${script}" "${p}" "$mtime" "${url}" "$concurrency" "$threshold"
		fi
	fi
done

echo "Optimizations done at $(date -uR)"
echo "----------------------------------"
echo
