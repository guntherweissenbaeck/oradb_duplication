
#!/bin/bash

####################################################################################################
# Author:       Gunther Weißenbäck
# Date:         2023-10-09
# Version:      1.0
# Description:  This script is a template for remote database duplication tasks.
# Repo:         github.com/guntherweissenbaeck/remote_database_duplication
####################################################################################################


####################################################################################################
# REMOTE SERVER
####################################################################################################

# read the arguments from the command line as the remote server 
# in the style of -r <remote_server>
# example: ./duplicate_script.sh -r remote_server
# if no argument is given, the script will exit
while getopts r: option; do
    case "${option}" in
        r) remote_server=${OPTARG} ;;
    esac
done

# remote server in uppercase as the same variable
$remote_server=$(echo "$remote_server" | tr '[:lower:]' '[:upper:]')

# local server = local database instance
local_database_instance=$(echo "$HOSTNAME" | cut -d'_' -f1)

# remote server = remote database instance
remote_database_instance=$(echo "$remote_server" | cut -d'.' -f1)

####################################################################################################
# Check if the remote server is reachable
####################################################################################################

# check if the remote server is reachable
if ping -q -c 1 -W 1 "$remote_server" >/dev/null; then
        echo "The remote server $remote_server is reachable"
else
    echo "The remote server $remote_server is not reachable"
    # exit the script
    exit 1
fi

# check if the remote server is reachable over port 22
if nc -z -w 1 "$remote_server" 22 >/dev/null; then
    echo "The remote server $remote_server is reachable over port 22"
else
    echo "The remote server $remote_server is not reachable over port 22"
    # exit the script
    exit 1
fi

# check if the remote server is reachable over port 22 using passwordless authentication
if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$remote_server" true >/dev/null 2>&1; then
    echo "The remote server is $remote_server reachable over port 22 using passwordless authentication"
else
    echo "The remote server $remote_server is not reachable over port 22 using passwordless authentication"
    # exit the script
    exit 1
fi

####################################################################################################
# Check if the local and remote server are database servers
####################################################################################################

# check if the local server is a database server
if ps -ef | grep pmon | grep -v grep >/dev/null; then
    echo "The local server is an oracle database server."
else
    echo "The local server is not an oracle database server."
    # exit the script
    exit 1
fi

# check if the remote server is a database server
if ssh "$remote_server" "ps -ef | grep pmon | grep -v grep" >/dev/null; then
    echo "The remote server $remote_server is an oracle database server"
else
    echo "The remote server $remote_server is not an oracle database server"
    # exit the script
    exit 1
fi

####################################################################################################
# Temporay Password change for the users sys and system
####################################################################################################

# get the encrypted password for the user sys and system from the local database and write it to a file
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
set heading off
set feedback off
set pagesize 0
set linesize 1000
SELECT password FROM sys.user\$ WHERE name = 'SYS';
SELECT password FROM sys.user\$ WHERE name = 'SYSTEM';
exit;
EOF > /tmp/passwords_local.txt

# get the encrypted password for the user sys and system from the remote database and write it to a file
ssh "$remote_server" "sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
set heading off
set feedback off
set pagesize 0
set linesize 1000
SELECT password FROM sys.user\$ WHERE name = 'SYS';
SELECT password FROM sys.user\$ WHERE name = 'SYSTEM';
exit;
EOF" >> /tmp/passwords_remote.txt

# hide passwordfile from other users
chmod 600 /tmp/passwords_local.txt
chmod 600 /tmp/passwords_remote.txt

# generate a random password for the user sys and system
random_password_sys=$(openssl rand -base64 12)
random_password_system=$(openssl rand -base64 12)

# change the password for the user sys and system in the local database using the random password
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter user sys identified by $random_password_sys;
alter user system identified by $random_password_system;
exit;
EOF

# use the random passwords and change the password for the user sys and system in the remote database
ssh "$remote_server" "sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter user sys identified by $random_password_sys;
alter user system identified by $random_password_system;
exit;
EOF"

####################################################################################################
# Create a duplication of the local database to the remote server using RMAN
####################################################################################################

# create a backup of the local database
rman target / <<EOF
backup database format '/oradump/dump.dmp';
exit;
EOF

# copy the backup to the remote server
scp /oradump/dump.dmp "$remote_server":/oradump/dump.dmp

# delete the temporary file
rm /oradump/dump.dmp

# check if the dump file exists on the remote server
if ssh "$remote_server" "[ -r /oradump/dump.dmp ]"; then
    echo "The dump file exists on the remote server $remote_server_uppercase. Starting the duplication process."
    # create a duplication of the local database to the remote server using RMAN and the backup
    # in the folder /oradump/dump.dmp
    ssh "$remote_server" "rman target / <<EOF
    duplicate target database to $remote_server_uppercase from '/oradump/dump.dmp';
    exit;
    EOF"
    # remove the backup from the remote server
    ssh "$remote_server" "rm /oradump/dump.dmp"
else
    echo "The dump file does not exist on the remote server $remote_server_uppercase"
    # exit the script
    exit 1
fi

####################################################################################################
# Change the password for the user sys and system
####################################################################################################


# change the password for the user sys and system in the local database using the encrypted password
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter user sys identified by values '$(cat /tmp/passwords_local.txt | head -n 1)';
alter user system identified by values '$(cat /tmp/passwords_local.txt | tail -n 1)';
exit;
EOF

# use the encrypted passwords and change the password for the user sys and system in the remote database
ssh "$remote_server" "sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter user sys identified by values '$(cat /tmp/passwords_remote.txt | head -n 1)';
alter user system identified by values '$(cat /tmp/passwords_remote.txt | tail -n 1)';
exit;
EOF"

# delete the temporary files
rm /tmp/dump.txt
rm /tmp/passwords_local.txt

####################################################################################################
# Delete a backup user on the remote server
####################################################################################################

# delete user voratest on the remote database
ssh "$remote_server" "sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
drop user voratest cascade;
exit;
EOF"

####################################################################################################
# Post database administration tasks
####################################################################################################

# check if post database administration script exists and is readable on the remote server
if ssh "$remote_server" "[ -r /home/oracle/Documents/post_database_duplication.sh ]"; then
    # execute the post database administration script on the remote server
    ssh "$remote_server" "/home/oracle/Documents/post_database_duplication.sh"
    echo "The database post duplication tasks for the remote server $remote_server_uppercase are completed!"
else
    echo "No Post database duplication script exist on the remote server $remote_server".
fi

####################################################################################################
# Success message of duplication
####################################################################################################
echo "The database duplication from the local server to the remote server $remote_server_uppercase is completed!"
