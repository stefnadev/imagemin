#!/bin/bash

PROG=$0
STOPFILE=".noImageMin"
NICE="3"

usage() {
	echo "Usage: ${PROG} mtime dir... " >&2
	echo -e "\tmtime 0 to skip mtime, else this is used in the find commands " >&2
	echo >&2
	exit 1
}

errorMsg() {
	echo -e "\e[31m$1\e[0m" >&2
	if [ "$2" != "" ]; then
		echo "$2"  >&2
	fi
	echo >&2
}
error() {
	errorMsg "$1" "$2"
	usage
}
warn() {
	echo -ne "\e[2m$1\e[0m"
}
green() {
	echo -ne "\e[32m$1\e[0m"
}
yellow() {
	echo -ne "\e[33m$1\e[0m"
}

dir=$(dirname ${PROG})
script="$dir/imagemin.sh"
if [ ! -f ${script} ]; then
	error "Could not find script" "$script"
fi

if [ "$1" == '--help' -o "$1" == '-h' ]; then
	usage
fi
if [ $# -lt 1 ]; then
	error "Missing arguments"
fi

mtime=${1//[^0-9]/}
shift

if [ $# -lt 1 ]; then
	error "No directories given"
fi

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
			nice -n ${NICE} "${script}" "${p}" "$mtime"
		fi
	fi
done
