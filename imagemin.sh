#!/bin/bash

function usage() {
	echo -e "\tUsage: $0: PATH [MTIME]\n" >&2
	echo -e "\t\tPATH:  Path to image files" >&2
	echo -e "\t\tMTIME: Optional: Find files modified less than MTIME days ago" >&2
	echo  >&2
	if [ "$1" != "" ]; then
		exit $1
	else
		exit 1
	fi
}
function errorMsg() {
	echo -e "\e[31m$1\e[0m" >&2
	if [ "$2" != "" ]; then
		echo "$2"  >&2
	fi
	echo >&2
}
function error() {
	errorMsg "$1" "$2"
	usage $3
}
function warn() {
	echo -ne "\e[2m$1\e[0m"
}
function green() {
	echo -ne "\e[32m$1\e[0m"
}
function yellow() {
	echo -ne "\e[33m$1\e[0m"
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

# Check for compressors
CMDOPTIPNG=$(command -v optipng)
CMDMOZJPEG=$(command -v mozjpeg)

if [ "$CMDOPTIPNG" == "" -o "$CMDMOZJPEG" == "" ]; then
	error "Could not find compressors." "Please install as root: npm install -g optipng-bin mozjpeg" 3
fi

# Check for imagemagick
CMDCONVERT=$(command -v convert)

if [ "$CMDCONVERT" == "" ]; then
	error "Could not find imagemagick." "Please install the latest version" 3
fi

# Create temporary filename
# Use the /tmp folder because it might be on another file system (performance)
TEMPFILE="/tmp/imagemin___temp___"

# Maximum dimension of image
MAXIMAGEDIMENSION=2000

function getJpegCmd() {
	${CMDMOZJPEG} -progressive -optimize -outfile "$2" "$1"
}
function getPngCmd() {
	${CMDOPTIPNG} -silent -strip all -o2 -out "$2" "$1"
}
function removeTempFile() {
	# remove any existing tempfile
	if [ -f "$TEMPFILE" ]; then
		rm "$TEMPFILE"
	fi
}
function perc() {
	p=$(( ($1*100)/$2 ))
	printf "%.0f" "${p}"
}
function shrinkFile() {
	removeTempFile

	f="$1"
	sizeBefore=$(stat -c%s "$f")

	${CMDCONVERT} "$f" -resize "${MAXIMAGEDIMENSION}x${MAXIMAGEDIMENSION}>" ${TEMPFILE}

	if [ -f "$TEMPFILE" ]; then
		sizeAfter=$(stat -c%s "$TEMPFILE")
		diff=$(( ${sizeBefore} - ${sizeAfter} ))
		if [ ${diff} -gt 0 -a ${sizeAfter} -gt 32 ]; then
			perc=$(perc ${diff} ${sizeBefore})
			yellow "($perc%) "
			chown --reference="$f" "$TEMPFILE" && \
			chmod --reference="$f" "$TEMPFILE" && \
			mv "$TEMPFILE" "$f"
		fi
	fi
}
function optimizeFile() {
	removeTempFile

	f="$1"
	cmd="$2"
	sizeBefore=$(stat -c%s "$f")

	${cmd} "$f" "$TEMPFILE"
	
	if [ -f "$TEMPFILE" ]; then
		sizeAfter=$(stat -c%s "$TEMPFILE")
		if [ ${sizeAfter} -gt 32 ]; then
			diff=$(( ${sizeBefore} - ${sizeAfter} ))

			if [ ${diff} -gt 0 ]; then
				perc=$(perc ${diff} ${sizeBefore})
				green "($perc%)"
				chown --reference="$f" "$TEMPFILE" && \
				chmod --reference="$f" "$TEMPFILE" && \
				mv "$TEMPFILE" "$f"
				if [ $? -ne 0 ]; then
					errorMsg "Optimization failed!" "Could not prepare new file"
				fi
			else
				warn "No optimization"
			fi
		else
			errorMsg "Optimization failed!" "Temporary file zero bytes."
		fi
	else
		errorMsg "Optimization failed!" "Temporary file not created."
	fi
}
function findCommand() {
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
function optimizeDir() {
	cmd=$1
	shift
	findCmd=$(findCommand $@)

	time=$(date +%s)

	# we need to use while read to optimize files with space in filename
	find "$IMAGEPATH" ${findCmd} | while read -r FILE; do
		echo -n "$FILE: "
		shrinkFile "$FILE"
		optimizeFile "$FILE" "$cmd"
		ltime=$(date +%s)
		echo " ($(( $ltime - $time )) sec)" # New line
		time=${ltime}
	done
}

# for debugging
#set -x

# no globbing #TODO Comment on why no globbing
set -f

optimizeDir getPngCmd png
optimizeDir getJpegCmd jpg jpeg
removeTempFile
