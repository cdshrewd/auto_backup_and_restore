# auto_backup_and_restore
auto backup oracle db and restore to another instance
We can use generate_auto_fullbackup_for_pitr.sh to build a disk type backup for source database.
We can use generate_auto_restore_db_for_pitr.sh to restore database from disk type backup to other instance.
It will prompt time or scn range for your point in time recovery.
We can use generate_auto_restore_db_for_pitr_from_sbt.sh to restore database from sbt_tape type backup to other instance.
It will prompt time or scn range for your point in time recovery.



Name:generate_auto_fullbackup_for_pitr.sh

Author:cdshrewd (cdshrewd#163.com)

Purpose:Generate full backup for pitr testing.

Usage:It should be run by root.You can run it like this:

'./generate_auto_fullbackup_for_pitr.sh -pri_db_name 'oradb' 
  -pri_backup_dir '/u01/app/backup' -run_backup_now 'yes/no'.

If you provide run_backup_now with yes.It will generate a fullbackup
script with name $RMAN_AUTO_BACKUP_SCRIPT and runs automatically.
This script will create shell file in current direcory.
You should make these directories avaliable.
Modified Date:2017/07/26




Name:generate_pitr_script.sh
Author:cdshrewd (cdshrewd#163.com)
Purpose:Generate Point In-Time Recovery scripts.
Usage:It should be run by root.You can run it like this:
'./generate_auto_restore_db_for_pitr.sh -tgt_inst_name 'oradbdg'  
  -target_data_dir  '/u01/app/oracle/oradata/oradbdg' 
  -ctrl_backup_loc '/u01/app/backup'
  -db_backup_dir '/u01/app/backup'
  -auto_resetlogs 'yes'.
  
If you provide auto_resetlogs with yes.It will generate a restore and recover 
  script with name auto_pitr_db_by_cdshrewd.sh and runs automatically with open resetlogs.
  This script will create shell file in current direcory.
 You should make all refered directories avaliable.
Modified Date:2017/08/29


Name:generate_pitr_script.sh
Author:cdshrewd (cdshrewd#163.com)
Purpose:Generate Point In-Time Recovery scripts.
Usage:It should be run by root.You can run it like this:
'./generate_auto_restore_db_for_pitr.sh -tgt_inst_name 'oradbdg' 
 -target_data_dir  '/u01/app/oracle/oradata/oradbdg' 
 -ctrl_backup_loc '/ctrl_backup_by_cdshrewd.bk'
 -rman_channel_params 'NB_ORA_CLIENT=db01,NB_ORA_SERV=nbuserver'
 -auto_resetlogs 'yes'.

If you provide auto_resetlogs with yes.It will generate a restore and recover 
 script with name auto_pitr_db_by_cdshrewd.sh and runs automatically with open resetlogs.
This script will create shell file in current direcory.
You should make all refered directories avaliable.
Modified Date:2017/08/29

