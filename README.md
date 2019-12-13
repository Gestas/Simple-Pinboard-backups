## Simple Pinboard.in backups
Simple tool to create a local backup of your Pinboard.in bookmarks and notes.

Requires jq.

### INSTALLATION:
```
$ wget -O /usr/local/bin/pinboard-backuper.sh \
	https://raw.githubusercontent.com/Gestas/Simple-Pinboard-backups/master/Pinboard-backuper.sh
$ chmod +x /usr/local/bin/pinboard-backuper.sh
```

### USAGE: 
```
All arguments are required.
ARGUMENTS:
	?   Display this help.
	-t   Pinboard API token in <username>:<token> format. See https://pinboard.in/settings/password. 
	-p   Path to destination folder.
	-r   Count of prior backups to retain. Use "0" to never delete old backups.
	-v   Verbose (0 | 1)
	-d   DEBUG (0 | 1)
```
A crontab entry would look something like -
```
0 1 * * * Pinboard-backuper.sh -t "<token>" -p "<destination path>" -r <retention>  -v 0 -d 0
```
