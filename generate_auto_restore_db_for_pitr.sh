#!/bin/bash
###############################################
# Name:generate_pitr_script.sh
# Author:cdshrewd (cdshrewd#163.com)
# Purpose:Generate Point In-Time Recovery scripts.
# Usage:It should be run by root.You can run it like this:
# './generate_auto_restore_db_for_pitr.sh -tgt_inst_name 'oradbdg' \ 
#  -target_data_dir  '/u01/app/oracle/oradata/oradbdg' \
#  -ctrl_backup_loc '/u01/app/backup'
#  -db_backup_dir '/u01/app/backup'
#  -auto_resetlogs 'yes'.
#  If you provide auto_resetlogs with yes.It will generate a restore and recover 
#  script with name auto_pitr_db_by_cdshrewd.sh and runs automatically with open resetlogs.
#  This script will create shell file in current direcory.
#  You should make all refered directories avaliable.
# Modified Date:2017/08/29
###############################################
# set -x
DB_BACKUP_DIR=""
TGT_ORCL_USER=`ps -ef|grep ora_smon|grep -v grep|head -1|awk '{print $1}'`
RMAN_LOG_PREFIX="auto_pitr_restore_cdshrewd_"
RMAN_LOG_SUFFIX=".out"
AUTO_RESETLOGS="no"
RECOVER_TYPE="time"
TGT_ORCL_USER_HOME=`grep ^$TGT_ORCL_USER /etc/passwd|awk -F ':' '{print $6}'`
if [ $# -lt 4 ]; then
        echo "You must provide 5 params.The params tgt_inst_name,"
        echo "db_backup_dir,ctrl_backup_loc and target_data_dir are required. "
        echo "You can use this script likes: \"$0 \\"
        echo " -tgt_inst_name 'oradbdg' \\"
        echo " -ctrl_backup_loc '/u01/app/backup/ctrl_backup_by_cdshrewd.bk' \\"
	echo " -db_backup_dir '/u01/app/backup' \\"
        echo " -target_data_dir '/u01/app/oracle/oradata/oradbdg' \\"
        echo " -recover_type 'time' \\"
        echo " -auto_resetlogs 'no'"
        exit 1
fi
while [ $# -gt 0 ]
  do
    case $1 in
      -tgt_inst_name) shift;TGT_INST_NAME=$1;;         # target db_unique_name is set 
      -db_backup_dir) shift; DB_BACKUP_DIR=$1; export DB_BACKUP_DIR;;  # DB_BACKUP_DIR is set
      -ctrl_backup_loc) shift; CONTROLFILE_BACKUP_LOC=$1; export CONTROLFILE_BACKUP_LOC;;  # CONTROLFILE_BACKUP_LOC is set
      -target_data_dir) shift; TARGET_DATA_DIR=$1;;  # TARGET_DATA_DIR is set
      -recover_type) shift; RECOVER_TYPE=$1;;  # TARGET_DATA_DIR is set
      -auto_resetlogs) shift; AUTO_RESETLOGS=$1;;  # AUTO_RESETLOGS is set
    esac;
    shift
  done

if [ -z $CONTROLFILE_BACKUP_LOC -o -z $TGT_INST_NAME ]; then
        echo "You must provide at least 2 params.The params ctrl_backup_loc,tgt_inst_name are required. "
	exit 1
fi
# get  dir from file path
get_dir_from_filepath()
{
file_name=$1
dir=`pwd`
if [[ "$file_name" =~ ^/  ]]; then
let pos=`echo "$file_name" | awk -F '/' '{printf "%d", length($0)-length($NF)}'`
dir=${file_name:0:pos-1}
fi
echo "$dir"
}

if [ -z $DB_BACKUP_DIR ]; then
DB_BACKUP_DIR=`get_dir_from_filepath $CONTROLFILE_BACKUP_LOC`
fi
# restore control file and mount database
restore_ctrl_mount_db()
{
USERNAME=$TGT_ORCL_USER
USER_HOME=`grep ^$USERNAME /etc/passwd|awk -F ':' '{print $6}'`
. $USER_HOME/.bash_profile
instance_status=1
process_status=0
process_status=`ps -ef|grep ora_smon_${TGT_INST_NAME}|grep -v grep|wc -l`
su - $USERNAME <<EOF
export ORACLE_SID=$TGT_INST_NAME
if [ $process_status -eq 1 ] ; then
sqlplus -S / as sysdba << INST_STATUS
set heading off feedback off pagesize 0 verify off echo off
col status new_value inst_status
select decode(status,'STARTED',0,2) status from v\\\$instance;
exit inst_status
exit
INST_STATUS
else
echo "instance $TGT_INST_NAME did not start.Pls start instance $TGT_INST_NAME in nomount mode."
exit 1
fi
EOF
instance_status=$?
if [ $instance_status -eq 0 ]; then
su - $USERNAME <<EOF
export ORACLE_SID=$TGT_INST_NAME
rman target / <<RMAN
restore controlfile from '$CONTROLFILE_BACKUP_LOC';
sql 'alter database mount';
exit
RMAN
exit
EOF
elif [ $instance_status -eq 1 ]; then
echo "instance $TGT_INST_NAME did not start.We will try to start it."
su - $USERNAME <<EOF
export ORACLE_SID=$TGT_INST_NAME
sqlplus / as sysdba <<SQL
startup nomount;
exit
SQL
rman target / <<RMAN
restore controlfile from '$CONTROLFILE_BACKUP_LOC';
sql 'alter database mount';
exit
RMAN
exit
EOF
else
echo "instance is up but not in nomount mode!Pls check $TGT_INST_NAME is right or wrong."
exit 2
fi
}
restore_ctrl_mount_db

GET_TIME_RANGE_SCRIPT=$DB_BACKUP_DIR/get_time_range.sh
GET_SCN_RANGE_SCRIPT=$DB_BACKUP_DIR/get_scn_range.sh
generate_recover_range()
{
USERNAME=$TGT_ORCL_USER
USER_HOME=`grep ^$USERNAME /etc/passwd|awk -F ':' '{print $6}'`
echo ". $USER_HOME/.bash_profile" >$GET_TIME_RANGE_SCRIPT
echo "su - $USERNAME <<EOF" >>$GET_TIME_RANGE_SCRIPT
echo "export ORACLE_SID=$TGT_INST_NAME" >>$GET_TIME_RANGE_SCRIPT
echo "sqlplus -S / as sysdba <<\"SCN\"" >>$GET_TIME_RANGE_SCRIPT
echo "set heading off feedback off pagesize 0 linesize 500" >>$GET_TIME_RANGE_SCRIPT
echo "select 'time range:'||(select to_char(max(CHECKPOINT_TIME),'yyyy-mm-dd hh24:mi:ss') from v\\\$datafile)||' to '||(select to_char(max(NEXT_TIME),'yyyy-mm-dd hh24:mi:ss') from v\\\$archived_log) as time_range from dual;" >>$GET_TIME_RANGE_SCRIPT
echo "exit;" >>$GET_TIME_RANGE_SCRIPT
echo "SCN" >>$GET_TIME_RANGE_SCRIPT
echo "exit;" >>$GET_TIME_RANGE_SCRIPT
echo "EOF" >>$GET_TIME_RANGE_SCRIPT

chmod a+x $GET_TIME_RANGE_SCRIPT

echo ". $USER_HOME/.bash_profile" >$GET_SCN_RANGE_SCRIPT
echo "su - $USERNAME <<EOF" >>$GET_SCN_RANGE_SCRIPT
echo "export ORACLE_SID=$TGT_INST_NAME" >>$GET_SCN_RANGE_SCRIPT
echo "sqlplus -S / as sysdba <<\"SCN\"" >>$GET_SCN_RANGE_SCRIPT
echo "set heading off feedback off pagesize 0 linesize 500" >>$GET_SCN_RANGE_SCRIPT
echo "select 'scn range:'||(select max(CHECKPOINT_CHANGE#) from v\\\$datafile)||' to '||(select max(NEXT_CHANGE#) from v\\\$archived_log) as scn_range from dual;" >>$GET_SCN_RANGE_SCRIPT
echo "exit;" >>$GET_SCN_RANGE_SCRIPT
echo "SCN" >>$GET_SCN_RANGE_SCRIPT
echo "exit;" >>$GET_SCN_RANGE_SCRIPT
echo "EOF" >>$GET_SCN_RANGE_SCRIPT
chmod a+x $GET_SCN_RANGE_SCRIPT
}
generate_recover_range

TIME_RANGE=""
SCN_RANGE=""
if [ $RECOVER_TYPE == "time" ]; then
TIME_RANGE=`$GET_TIME_RANGE_SCRIPT`
echo "You can specify time with $TIME_RANGE"
read -p "pls input time(format:yyyy-mm-dd hh24:mi:ss):" time
elif [ $RECOVER_TYPE == "scn" ]; then
SCN_RANGE=`$GET_SCN_RANGE_SCRIPT`
echo "You can specify scn with $SCN_RANGE:"
read -p "pls input scn" scn
else
echo "You did not provide right recover type.It will recover to the max scn record by controlfile."
SCN_RANGE=`$GET_SCN_RANGE_SCRIPT`
scn=`echo $SCN_RANGE|gawk -F"to " '{print $2}'`
fi

DB_FILE_NAME_CONVERT=$DB_BACKUP_DIR/auto_dbfile_name_convert_by_cdshrewd.out
db_file_name_convert()
{
USERNAME=$TGT_ORCL_USER
TARGET_DIR=$1
su - $USERNAME <<EOF
export ORACLE_SID=$TGT_INST_NAME
sqlplus -S / as sysdba <<SQL >$DB_FILE_NAME_CONVERT
set heading off feedback off pagesize 0 
select 'set newname for datafile '||df.file#||' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.NAME, INSTR(df.NAME, '/', -1) + 1)||''';'  from v\\\$datafile df union
select 'set newname for tempfile '||df.file#||' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.NAME, INSTR(df.NAME, '/', -1) + 1)||''';'  from v\\\$tempfile df;
exit
SQL
exit
EOF
}

REDO_FILE_NAME_CONVERT=$DB_BACKUP_DIR/auto_redo_file_name_convert_by_cdshrewd.out
redo_file_name_convert()
{
USERNAME=$TGT_ORCL_USER
TARGET_DIR=$1
su - $USERNAME <<EOF
export ORACLE_SID=$TGT_INST_NAME
sqlplus -S / as sysdba <<SQL >$REDO_FILE_NAME_CONVERT
set heading off feedback off pagesize 0 linesize 500
select 'alter database rename file '''||df.member||''' to '''||'${TARGET_DIR}'||'/'||SUBSTR(df.member, INSTR(df.member, '/', -1) + 1)||''';'  from v\\\$logfile df ;
exit
SQL
exit
EOF
}


ONLINE_LOG_DIR=$DB_BACKUP_DIR/auto_online_logfile_by_cdshrewd.out
AUTO_RESTORE_SCRIPT=${DB_BACKUP_DIR}/auto_restore_db_by_cdshrewd.sh
echo $AUTO_RESTORE_SCRIPT
if [ -n $TARGET_DATA_DIR ]; then
db_file_name_convert $TARGET_DATA_DIR
redo_file_name_convert $TARGET_DATA_DIR
else
echo /dev/null>$DB_FILE_NAME_CONVERT
fi
cnt=0
cnt=`cat /proc/cpuinfo|grep processor|wc -l`
a=1
cnt=`expr $cnt / $a`
if [ $cnt -lt 1 ]; then
    cnt=1
fi
	echo "su - $TGT_ORCL_USER <<EOF" >$AUTO_RESTORE_SCRIPT
	echo "export ORACLE_SID=$TGT_INST_NAME" >>$AUTO_RESTORE_SCRIPT
        if [ -n $DB_BACKUP_DIR ]; then
             RMAN_LOG_FILE="$DB_BACKUP_DIR"/"${RMAN_LOG_PREFIX}"`date +%Y%m%dT%H%M`"${RMAN_LOG_SUFFIX}"
        else
        RMAN_LOG_FILE="${RMAN_LOG_PREFIX}"`date +%Y%m%dT%H%M`"${RMAN_LOG_SUFFIX}"
        fi
        echo "rman target / msglog='$RMAN_LOG_FILE' append<<RMAN">>$AUTO_RESTORE_SCRIPT
        echo "crosscheck backup;">>$AUTO_RESTORE_SCRIPT
        echo "delete noprompt expired backupset;">>$AUTO_RESTORE_SCRIPT
        for p in `ls -l $DB_BACKUP_DIR/auto_fulldb_*by_cdshrewd.bk|awk  '{print $NF}'`
        do
        echo "catalog  DEVICE TYPE 'DISK' BACKUPPIECE '$p';" >>$AUTO_RESTORE_SCRIPT
        done
        echo "run{">>$AUTO_RESTORE_SCRIPT
        for j  in $(seq $cnt )
        do
                echo "allocate channel ch0$j type disk;">>$AUTO_RESTORE_SCRIPT
                if [ $j -eq $cnt ]; then
                        if [ $RECOVER_TYPE == "time" ]; then
                        echo "sql 'alter session set nls_date_format= \"YYYY-MM-DD HH24:MI:SS\"';" >>$AUTO_RESTORE_SCRIPT
                        echo "set until time '${time}';" >>$AUTO_RESTORE_SCRIPT
                        elif [ $RECOVER_TYPE == "scn" ]; then
                        echo "set until scn=${scn};" >>$AUTO_RESTORE_SCRIPT
                        fi
                        cat $DB_FILE_NAME_CONVERT >>$AUTO_RESTORE_SCRIPT
                        echo "restore database;" >>$AUTO_RESTORE_SCRIPT
                        echo "switch datafile all;" >>$AUTO_RESTORE_SCRIPT
                        echo "switch tempfile all;" >>$AUTO_RESTORE_SCRIPT
                        echo "recover database;"  >>$AUTO_RESTORE_SCRIPT
                fi
        done

        for (( i=1; i<=$cnt; i++ ))
        do
                echo "release channel ch0$i;">>$AUTO_RESTORE_SCRIPT
                if [ $i -eq $cnt ]; then
                        echo "}" >>$AUTO_RESTORE_SCRIPT
                        echo "exit" >>$AUTO_RESTORE_SCRIPT
                        echo "RMAN" >>$AUTO_RESTORE_SCRIPT
                fi
        done
echo "exit;" >>$AUTO_RESTORE_SCRIPT
echo "EOF" >>$AUTO_RESTORE_SCRIPT
echo "su - $TGT_ORCL_USER <<EOFIN" >>$AUTO_RESTORE_SCRIPT
echo "export ORACLE_SID=$TGT_INST_NAME" >>$AUTO_RESTORE_SCRIPT
echo "sqlplus -S / as sysdba <<SQL" >>$AUTO_RESTORE_SCRIPT
cat ${REDO_FILE_NAME_CONVERT} >>$AUTO_RESTORE_SCRIPT
if [ $AUTO_RESETLOGS == "yes" ] ; then
echo "alter database open resetlogs;"  >>$AUTO_RESTORE_SCRIPT
fi
echo "exit;" >>$AUTO_RESTORE_SCRIPT
echo "SQL" >>$AUTO_RESTORE_SCRIPT
echo "exit;" >>$AUTO_RESTORE_SCRIPT
echo "EOFIN" >>$AUTO_RESTORE_SCRIPT
chmod u+x $AUTO_RESTORE_SCRIPT
nohup $AUTO_RESTORE_SCRIPT &

