#!/usr/bin/env bash

. $(dirname $0)/funcs.sh

PID=$$
TEMPFILE=/tmp/_imagemin_temp_${PID}

removeTempFile() {
	# remove any existing tempfile
	if [ -f "$TEMPFILE" ]; then
		rm "$TEMPFILE"
	fi
}
postFile() {
	local input="$1"
	local output="$2"
	local url="$3"
	local real=$(realpath "${input}")
	real=${real// /%20}
	local headers=$(curl -s -D - -w "%{http_code}" -o "$output" \
		--retry 5 --retry-delay 5 \
		-H "Expect:" -H "Content-Type: multipart/form-data" \
		-F "img=@$input" "${url}${real}")
	formatResponse "$headers" "$output"
}
formatResponse() {
	local tmpFile="$2"
	local r=${1//$'\r'/}
	local code="${r##*$'\n'}"
	local line=, shrink=, optimize=, total=, err=

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
	elif [ "$code" == "204" ]; then
		warn "No optimization"
	else
		if [ "$tmpFile" != "" -a -f "$tmpFile" ]; then
			err=$(tail -n 1 "${tmpFile}")
			rm "$tmpFile"
		fi
		warn "Bad Response code ($code): $err"
	fi
}
optimizeFile() {
	removeTempFile

	local f="$1"
	local url="$2"

	local optRes="$(postFile "$f" "$TEMPFILE" "$url")"

	if [ -f "$TEMPFILE" ]; then
		local sizeAfter=$(stat -c%s "$TEMPFILE")
		if [ ${sizeAfter} -gt 32 ]; then
			local tmpDate=$(date +%Y%m%d%H%I.%S -r "$f")
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
usage() {
	echo "Usage: $0 URL FILE" >&2
	exit 1
}

if [ $# -lt 2 ]; then
	usage
fi

url="$1"
shift
# So it is easier to process files with spaces
file="$*"
if [ ! -f "$file" ]; then
	error "'$file' is not a file"
fi
time=$(date +%s)

res=$(optimizeFile "$file" "$url")
ltime=$(date +%s)
# Echo in one line to try to keep line content together when running in parallel
echo "$file: $res ($(( $ltime - $time )) sec)"
# Just in case
removeTempFile
