
trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
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
escape() {
	printf '%q' "$1"
}
ping() {
	local url="$1"
	local ping=$(curl -s -w "%{http_code}" "$url/ping")
	if [ "$ping" != "200" ]; then
		error "Could not contact server"
	fi
}
