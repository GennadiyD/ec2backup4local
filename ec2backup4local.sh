#!/bin/bash

LOG_F_NAME=$(dirname $0)/$(basename $0|sed -e "s/\.sh$/\.log/")

#date/time marker
DATE=$(date)
echo $DATE" ----------------------------"|/usr/bin/tee -a $LOG_F_NAME

#number of backup to keep
AWS_N_BACKUPS=7

SKIP=0
AWS_INSTANCE_ID=$(/usr/bin/ec2metadata --instance-id)
AWS_VOL_4BACKUP=$(/usr/local/bin/aws ec2 describe-instances --profile account40 --query 'Reservations[*].Instances[].[BlockDeviceMappings[*].Ebs.VolumeId]' --output text --filters "Name=instance-id,Values=$AWS_INSTANCE_ID")
AWS_INSTANCE_NAME=$(/usr/local/bin/aws ec2  --profile account40 describe-tags --filters "Name=resource-id,Values=$AWS_INSTANCE_ID" "Name=key,Values=Name" --output text | cut -f5)

echo "INSTANCE ID: . "$AWS_INSTANCE_ID" . "|/usr/bin/tee -a $LOG_F_NAME
echo "NAME:        . "$AWS_INSTANCE_NAME" . "|/usr/bin/tee -a $LOG_F_NAME
echo "VOLUME:      . "$AWS_VOL_4BACKUP" . "|/usr/bin/tee -a $LOG_F_NAME

for i in $AWS_VOL_4BACKUP ; do
   while read j; do
        echo ".. "$j|/usr/bin/tee -a $LOG_F_NAME
	CD=$(echo $(date +%s) " - " $(date -d $(echo $j|awk '{print $2}') +%s) |bc)
        #skip if found fresh backup (12h=43200sec)
	if [ $CD -le 43200 ] ; then SKIP=1 ; NOTE=$j ; fi
   done < <(/usr/local/bin/aws ec2 describe-snapshots --owner-ids self --profile account40 --filters Name=volume-id,Values=$i --query 'Snapshots[*].[State,StartTime,SnapshotId]' --output text)
   # remove oldest snapshots if required

   TEMP1=$(/usr/local/bin/aws ec2 describe-snapshots --owner-ids self --profile account40 --filters Name=volume-id,Values=$i --query 'Snapshots[*].[State,SnapshotId,StartTime]' --output text|sort -k 3 |column -t|cut -d. -f 1|awk '{print $3" "$2"  "$1}')
   if [ $(echo "$TEMP1"|grep -c " completed") -ge $AWS_N_BACKUPS ]
    then echo "remove old snapshots:"
         while read j ;do
            echo " --  $j"|/usr/bin/tee -a $LOG_F_NAME
            /usr/local/bin/aws ec2 delete-snapshot --profile account40 --snapshot-id $j
         done < <(echo "$TEMP1"|grep completed|sort|head -n -$AWS_N_BACKUPS|awk '{print $2}')
   fi

#   if [ $SKIP -eq 1 ]
#    then echo "WARNING: Found fresh backup - "$NOTE|/usr/bin/tee -a $LOG_F_NAME
#         echo "exit without backup"|/usr/bin/tee -a $LOG_F_NAME
#         exit 22
#   fi
   if [ -z "$NOTE" ]
    then echo "start backup:"|/usr/bin/tee -a $LOG_F_NAME
         /usr/local/bin/aws ec2 create-snapshot --profile account40 --volume-id $i --description "scheduled-backup"|/usr/bin/tee -a $LOG_F_NAME
   fi
   RESULT_REPORT=$(/usr/local/bin/aws ec2 describe-snapshots --owner-ids self --profile account40 --filters Name=volume-id,Values=$i --query 'Snapshots[*].[State,SnapshotId,StartTime]' --output text|sort -k 3 |column -t|cut -d. -f 1|awk '{print $3" "$2"  "$1}')
   RES1=$(echo "$RESULT_REPORT"|grep -c "completed")
   RES2=$(echo $(date +%s)" - "$(date -d $(echo "$RESULT_REPORT"|grep "completed"|awk '{print $1}'|sort|tail -n1) +%s)|bc)
   RES3=$(echo "$RESULT_REPORT"|tail -n 1|grep -c "pending")
   RES="Success"
   DETAILS="Details: "
   if [ $RES1 -ne $AWS_N_BACKUPS ]
    then RES="Warning"
         DETAILS="$DETAILS"$'\n'"   Тhe number of backups does not match the planned ($AWS_N_BACKUPS)"
   fi
   if [ $RES2 -ge 129600 ]
    then RES="Warning"
         DETAILS="$DETAILS"$'\n'"   Last completed backup older than 36 hrs"
   fi
   if [ $RES3 -eq 0 ]
    then RES="Warning"
         DETAILS="$DETAILS"$'\n'"   Not fount \"pendin\" status for the last backup"
   fi
   if [ $SKIP -eq 1 ]
    then RES="Warning"
         DETAILS="$DETAILS"$'\n'"   Found fresh backup - \"$NOTE\"."$'\n'$"    -- Exit without backup"
   fi
   if [ "$RES" = "Warning" ]
    then echo "$DETAILS"|/usr/bin/tee -a $LOG_F_NAME
   fi
   if [ "$RES" = "Success" ]
    then DETAILS=""
   fi
   SUBJECT="Backup Report [$RES] for \"$AWS_INSTANCE_NAME\" ($AWS_INSTANCE_ID)"
   REPORTPREFIX="Device: "$(hostname)""$'\n'$"Status: $RES"$'\n'$"Job: Daily Backup"$'\n\n'$"Script: $(realpath $0)"$'\n\n'$"$DETAILS"$'\n\n'

   /usr/local/bin/aws sns publish --topic-arn arn:aws:sns:us-east-1:407333521057:BackupNotification --subject "$SUBJECT" --message "$REPORTPREFIX""$RESULT_REPORT"|/usr/bin/tee -a $LOG_F_NAME

done

#aws ec2 describe-snapshots --owner-ids self --profile account40 --filters Name=volume-id,Values=vol-0de01e22d74e0229b --query 'Snapshots[*].[State,StartTime]' --output text
