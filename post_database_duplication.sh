#!/bin/bash

####################################################################################################
# Author:       Gunther Weißenbäck
# Date:         2023-10-09
# Version:      1.0
# Description:  This script is a template for remote database post duplication tasks.
# Repo:         github.com/guntherweissenbaeck/remote_database_duplication
####################################################################################################


# check the size of the temp tablespace and write it to a file
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
set pagesize 0 feedback off verify off heading off echo off;
spool /tmp/temp_tablespace_size.txt
select sum(bytes)/1024/1024 from dba_temp_files;
spool off;
exit;
EOF

# add a second temp file to the oracle database temp02.dbf
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter tablespace temp add tempfile '/oradata/temp02.dbf' size 100M autoextend on next 100M maxsize 1000M;
exit;
EOF

# delete the first temp file from the oracle database temp01.dbf
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter database tempfile '/oradata/temp01.dbf' drop including datafiles;
exit;
EOF

# delete the first temp file from the directory /oradb/temp01.dbf if it exists
if [ -f /oradb/temp01.dbf ]; then
    rm /oradb/temp01.dbf
fi

# add the first temp file to the oracle database temp01.dbf in the folder /oradb/temp01.dbf
# reading the size from the file /tmp/temp_tablespace_size.txt
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter tablespace temp add tempfile '/oradata/temp01.dbf' size 100M autoextend on next 100M maxsize 1000M;
exit;
EOF


# delete the second temp file from the oracle database temp02.dbf
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
alter database tempfile '/oradata/temp02.dbf' drop including datafiles;
exit;
EOF

# delete the second temp file from the directory /oradb/temp02.dbf if it exists
if [ -f /oradb/temp02.dbf ]; then
    rm /oradb/temp02.dbf
fi

# remove temporary tablespaces T_KD2_Temp
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
drop tablespace T_KD2_Temp including contents and datafiles;
exit;
EOF

# Remove the temporary tablespaces T_KD2_Temp file from /u02/oradb/T_KD2_Temp.dbf if it exists
if [ -f /u02/oradb/T_KD2_Temp.dbf ]; then
    rm /u02/oradb/T_KD2_Temp.dbf
fi

# add temporary tablespaces T_KD2_Temp as Bigfile
sqlplus -s /nolog <<EOF
sqlplus /@tns_alias
create bigfile tablespace T_KD2_Temp tempfile '/oradata/temp01.dbf' size 100M autoextend on next 100M maxsize 1000M;
exit;
EOF

# Message that the post database administration tasks are finished
echo "The post database administration tasks are finished."
