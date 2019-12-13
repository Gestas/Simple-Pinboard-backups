#!/bin/bash

# Simple script to backup bookmarks and notes from Pinboard. 
# See https://github.com/Gestas/Simple-Pinboard-backups/README.md

# Requires jq
set -o nounset
set -o errexit

DATE_DISPLAY_FORMAT="--iso-8601=minutes"
BOOKMARKS_FILENAME="bookmarks.json"
NOTES_FILENAME="notes.json"
LOG_FILE="pinboard-backups.log"
# How long to delay between API calls. Rate limits - https://pinboard.in/api/
RATE_SECS="5"

usage () {
/usr/bin/cat << EOF

usage: $0 <arguments>

This script creates local backups of Pinboard bookmarks and notes.
All arguments are required.

ARGUMENTS:
	 ?   Display this help.    
	-t   Pinboard API token in <username>:<token> format. See https://pinboard.in/settings/password. 
	-p   Path to destination folder.
	-r   Count of prior backups to retain. Use "0" to never delete old backups.
    	-v   Verbose (0 | 1)
    	-d   DEBUG (0 | 1)
For more information - https://github.com/Gestas/Simple-Pinboard-backups/README.md
EOF
exit 1
}

log() {
	# Write to log file, optionally to stdout.
	local _now
	local _path
	local _log_file
	local _verbose
    local _message

    _path="$DEST_PATH"
    _message="$1"
    _verbose="$VERBOSE"
    _log_file="$LOG_FILE"
    _now="$(date "$DATE_DISPLAY_FORMAT")"

    if [[ "$_verbose" -ne 0 ]]; then
   		printf "%s\n" "$_now: $_message"
    fi
    printf "%s\n" "$_now: $_message" >> "$_path/$_log_file"
}

date_format() {
	# Convert datetime between epoch and display format.
	local _re
	local _date
	local _new_val

	_date="$1"
	
	_re='^[0-9]+$'
	if [[ $_date =~ $_re ]]; then
		_new_val=$(date -d @"$_date" --iso-8601=minutes)
	else 
		_new_val="$(date -d "$_date" +%s)"
	fi
	echo "$_new_val"
}

do_get() {
	local _path
	local _auth
	local _rate
	local _format
	local _response
	local _exitcode
	local _endpoint

	_rate="$RATE_SECS"
	_path="$1"
	_format="format=json"
	_auth="auth_token=$TOKEN"
	_endpoint="https://api.pinboard.in/v1/"

	sleep "$_rate"
	set +o errexit
	_response="$(curl --silent --location  --fail \
		--url "$_endpoint$_path?$_auth&$_format")"
	_exitcode=$?
	set -o errexit
    if [[ "$_exitcode" -eq 22 ]]; then
    	log "Recieved a non-200 response from Pinboard."
    	exit 1
    elif [[ "$_exitcode" -ne 0 ]]; then
    	log "GET failed with exit code $_exitcode."
    	log "See exit code details at https://linux.die.net/man/1/curl"
    	exit 1
	fi
	echo "$_response"
}

backup_bookmarks() {
	local _folder
	local _filename
	local _url_path
	local _response
	local _file_path

	_folder="$1"
	_filename="$2"
	_url_path="posts/all"
	_file_path="$_folder/$_filename"

	mkdir -p "$_folder"
	log "Backing up bookmarks."
	_response="$(do_get "$_url_path")"
	echo "$_response" >> "$_file_path"
}

backup_notes() {
	# We get a list of notes then retrieve each note.
	# I would have liked to save the notes using the note title as the 
	# filename. Can't because titles is not a required field. 
	local _n
	local _folder
	local _url_path
	local _file_path
	local _filename
	local _node_ids
	local _notes_list
	local _note

	_folder="$1"
	_folder="$1/notes/"
	_filename="$2"
	_file_path="$_folder/$_filename"
	_url_path="notes/list"
	mkdir -p "$_folder"	

	log "Backing up notes."
	_notes_list=$(do_get "$_url_path")
	echo "$_notes_list" >> "$_file_path"
	_node_ids="$(echo "$_notes_list" | jq -r '.notes | .[] | .id')"
	for _n in $_node_ids; do
		_url_path="notes/$_n"
		_note="$(do_get "$_url_path")"
		echo "$_note" >> "$_folder/$_n"
	done
}

delete_backups() {
	local _b
	local -a _e
	local _b_cnt
	local _to_del
	local _folder
	local _del_cnt
	local _b_retain
	local -a _epochs
	local _b_folders
	local _bookmarks_file

	_folder="$1"
	_b_retain="$2"
	_bookmarks_file="$3"
	_b_folders="$(find "$_folder" -mindepth 1 -maxdepth 1 -type d)"
	for _b in $_b_folders; do
		_b="$(basename "$_b")"
		_b="$(date_format "$_b")"
		_e+=( "$_b" ) 
	done
	# Sort the array
	readarray -td '' _epochs < <(printf '%s\0' "${_e[@]}" | sort -z -r)
	_b_cnt=${#_epochs[@]}
	log "Deleting expired backups."
	if [[ "$_b_cnt" -gt "$_b_retain" ]]; then
		_del_cnt=$(( _b_cnt - _b_retain ))
		while [[ $_del_cnt -gt 0 ]]; do 
			_to_del=${_epochs[-1]}
			_to_del="$(date_format "$_to_del")"
			log "Deleting backup $_to_del."
			# Shouldn't use rm -rf in scripts so we iterate over the structure
			rm "$_folder/$_to_del/notes/"*
			rmdir "$_folder/$_to_del/notes"
			rm "$_folder/$_to_del/$_bookmarks_file"
			rmdir "$_folder/$_to_del"
			unset '_epochs[${#_epochs[@]}-1]'
			_del_cnt=$((_del_cnt-1))
		done
	fi
}

main() {
	local _now
	local _retain
	local _folder
	local _filename

	_now="$(date "$DATE_DISPLAY_FORMAT")"
	_folder="$DEST_PATH/$_now"
	_retain="$RETAIN"

	log "$0: Starting Pinboard.in backup."
	log "$_folder"
	_filename="$BOOKMARKS_FILENAME"
	backup_bookmarks "$_folder" "$_filename"
	_filename="$NOTES_FILENAME"
	backup_notes "$_folder" "$_filename"
	_filename="$BOOKMARKS_FILENAME"
	_folder="$DEST_PATH/"
	if [[ "$_retain" -gt 0 ]]; then
		delete_backups "$_folder" "$_retain" "$_filename"
	fi
	log "Pinboard.in backup complete."
	exit 0
}

while getopts ":t:p:r:v:d:" opt ; do
	case $opt in
		t ) TOKEN=$OPTARG ;;
		p ) DEST_PATH=$OPTARG ;;
		r ) RETAIN=$OPTARG ;;
		v ) VERBOSE=$OPTARG ;;
		d ) DEBUG=$OPTARG ;;
		\?) usage ;;
		 *) usage ;;
	esac
done

if [[ -z "$TOKEN" ]] || [[ -z "$DEST_PATH" ]] || [[ -z "$RETAIN" ]] || \
   [[ -z "$VERBOSE" ]] || [[ -z "$DEBUG" ]]; then
	if [[ "$DEBUG" -ne 0 ]]; then
		log "TOKEN: $TOKEN"
		log "DESTINATION PATH: $DEST_PATH"
		log "RETENTION COUNT: $RETAIN"
		log "VERBOSE: $VERBOSE"
		log "DEBUG: $DEBUG" 
	fi
	usage
fi

if [[ "${DEBUG}" -ne 0 ]]; then
	set -o xtrace functrace
fi

main
exit 0