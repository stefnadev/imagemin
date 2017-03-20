#!/bin/bash

defaultUrl="http://localhost:8082"

usage() {
	echo -e "\tUsage: $0: PATH [MTIME] [URL]\n" >&2
	echo -e "\t\tPATH:  Path to image files" >&2
	echo -e "\t\tMTIME: Optional: Find files modified less than MTIME days ago" >&2
	echo -e "\t\tURL:   Optional: Send request to URL (default=$defaultUrl)" >&2
	echo  >&2
	if [ "$1" != "" ]; then
		exit $1
	else
		exit 1
	fi
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
	usage $3
}
reset() {
	echo -ne "\e[0m"
}
red() {
	echo -ne "\e[31m$1\e[0m"
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

ping=$(curl -s -w "%{http_code}" "$URL/ping")
if [ "$ping" != "204" ]; then
	error "Could not contact server"
fi

# Create temporary filename
# Use the /tmp folder because it might be on another file system (performance)
TEMPFILE="/tmp/imagemin___temp___"

# Maximum dimension of image
MAXIMAGEDIMENSION=2000

removeTempFile() {
	# remove any existing tempfile
	if [ -f "$TEMPFILE" ]; then
		rm "$TEMPFILE"
	fi
}
postFile() {
	input="$1"
	output="$2"
	real=$(realpath "${input}")
	real=${real// /%20}
	headers=$(curl -s -D - -w "%{http_code}" -o "$output" \
		--retry 3 --retry-delay 5 \
		-H "Expect:" -H "Content-Type: multipart/form-data" \
		-F "img=@$input" "${URL}${real}")
	formatResponse "$headers" "$output"
}
formatResponse() {
	tmpFile="$2"
	r=${1//$'\r'/}
	code="${r##*$'\n'}"
	if [ "$code" == "200" ]; then
		if [[ "$r" =~ ST-Img-Result:.([^$'\n']+)\ *$'\n' ]]; then
			line="${BASH_REMATCH[1]}"
		else
			line=$(echo "$1"|grep ST-Img-Result|sed 's@.*: @@')
		fi
		if [ "$line" != "" ]; then
			read shrink optimize total <<<$(IFS=";"; echo ${line})
			yellow "${shrink} "
			yellow "${optimize} "
			green $(trim ${total})
		else
			warn "Could not parse headers"
		fi
	else
		err=
		if [ "$tmpFile" != "" -a -f "$tmpFile" ]; then
			err=$(tail -n 1 "${tmpFile}")
			rm "$tmpFile"
		fi
		warn "Bad Response code ($code): $err"
	fi
}
trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}
optimizeFile() {
	removeTempFile

	f="$1"
	cmd="$2"

	optRes="$(postFile "$f" "$TEMPFILE")"

	if [ -f "$TEMPFILE" ]; then
		sizeAfter=$(stat -c%s "$TEMPFILE")
		if [ ${sizeAfter} -gt 32 ]; then
			tmpDate=$(date +%Y%m%d%H%I.%S -r "$f")
			chown --reference="$f" "$TEMPFILE" && \
			chmod --reference="$f" "$TEMPFILE" && \
			mv "$TEMPFILE" "$f" && \
			touch -t "$tmpDate" "$f"
			if [ $? -ne 0 ]; then
				red "Could not prepare new file"
			else
				echo -n ${optRes}
			fi
		else
			warn "No optimization"
		fi
	else
		if [ "$optRes" == "" ]; then
			red "Temporary file not created."
		else
			red "$optRes"
		fi
	fi
}
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
optimizeDir() {
	findCmd=$(findCommand $@)

	time=$(date +%s)

	# we need to use while read to optimize files with space in filename
	find "$IMAGEPATH" ${findCmd} | while read -r FILE; do
		echo -n "$FILE: "
		optimizeFile "$FILE"
		ltime=$(date +%s)
		echo " ($(( $ltime - $time )) sec)" # New line
		time=${ltime}
	done
}

# for debugging
#set -x

# no globbing so we won't accidentally match some files while running find
set -f

optimizeDir png jpg jpeg
removeTempFile
