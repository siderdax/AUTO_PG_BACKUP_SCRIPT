#!/bin/bash

###########################
####### LOAD CONFIG #######
###########################

while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        CONFIG_FILE_PATH="$2"
                        shift 2
                        ;;
                *)
                        ${ECHO} "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done

if [ -z $CONFIG_FILE_PATH ] ; then
        SCRIPTPATH=$(cd ${0%/*} && pwd -P)
        CONFIG_FILE_PATH="${SCRIPTPATH}/pgs_backup.config"
fi

if [ ! -r ${CONFIG_FILE_PATH} ] ; then
        echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
        exit 1
fi

source "${CONFIG_FILE_PATH}"

###########################
#### PRE-BACKUP CHECKS ####
###########################

# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ] ; then
	echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
	exit 1
fi


###########################
### INITIALISE DEFAULTS ###
###########################

if [ -n $PGPASSWORD ]; then
	export PGPASSWORD=$PGPASSWORD
	echo "PGPASSWORD=$PGPASSWORD"
fi

ARG_ROL=""
ARG_ECD=""
ARG_DTRG=""

if [ -n $ROLE ]; then
	ARG_ROL="--role=$ROLE"
fi

if [ -n $ENCODING ]; then
	ARG_ECD="-E $ENCODING"
fi

if [ $DISABLE_TRIGGERS = "yes" ]; then
	ARG_DTRG="--disable-triggers"
fi

echo -e "\n\n###Checking advance options###"
echo "$ARG_ROL"
echo "$ARG_ECD"
echo "$ARG_DTRG"
echo -e "##############################\n"

# Set default username and hostname if doesn't exist
if [ ! $HOSTNAME ]; then
	HOSTNAME="localhost"
fi;

if [ ! $USERNAME ]; then
	USERNAME="postgres"
fi;

###########################
#### START THE BACKUPS ####
###########################

function perform_backups()
{
	SUFFIX=$1
	if [ $SUFFIX = "-hourly" ]
	then
		FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%dH\%H`$SUFFIX/"
	else
		FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"
	fi

	echo "Making backup directory in $FINAL_BACKUP_DIR"

	if ! mkdir -p $FINAL_BACKUP_DIR; then
		echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
		exit 1;
	fi;

	#######################
	### GLOBALS BACKUPS ###
	#######################

	if [ $SUFFIX = "-hourly" ]
	then
		echo -e "\n Hourly backup"
	else
		echo -e "\n\nPerforming globals backup"
		echo -e "--------------------------------------------\n"

		if [ $ENABLE_GLOBALS_BACKUPS = "yes" ]
		then
			if [ $USE_GZIP = "yes" ]
			then
				echo "Globals backup + gzip"
				if ! pg_dumpall -g -h "$HOSTNAME" -U "$USERNAME" $ARG_ROL $ARG_DTRG | gzip > $FINAL_BACKUP_DIR"globals".sql.gz.in_progress; then
					echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
				else
					mv $FINAL_BACKUP_DIR"globals".sql.gz.in_progress $FINAL_BACKUP_DIR"globals".sql.gz
				fi
			else
				echo "Globals backup"
				if ! pg_dumpall -g -h "$HOSTNAME" -U "$USERNAME" $ARG_ROL $ARG_DTRG -f $FINAL_BACKUP_DIR"globals".sql.in_progress; then
					echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
				else
					mv $FINAL_BACKUP_DIR"globals".sql.in_progress $FINAL_BACKUP_DIR"globals".sql
				fi
			fi
		else
			echo "None"
		fi
	fi


	###########################
	### SCHEMA-ONLY BACKUPS ###
	###########################

	for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
	do
	        SCHEMA_ONLY_CLAUSE="$SCHEMA_ONLY_CLAUSE or datname ~ '$SCHEMA_ONLY_DB'"
	done

	SCHEMA_ONLY_QUERY="select datname from pg_database where false $SCHEMA_ONLY_CLAUSE order by datname;"

	echo -e "\n\nPerforming schema-only backups"
	echo -e "--------------------------------------------\n"

	SCHEMA_ONLY_DB_LIST=`psql -h "$HOSTNAME" -U "$USERNAME" -At -c "$SCHEMA_ONLY_QUERY" postgres`

	echo -e "The following databases were matched for schema-only backup:\n${SCHEMA_ONLY_DB_LIST}\n"

	for DATABASE in $SCHEMA_ONLY_DB_LIST
	do
		if [ $USE_GZIP = "yes" ]
		then
			echo "Schema-only backup of $DATABASE + gzip"
			if ! pg_dump -s -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" $ARG_ROL $ARG_ECD $ARG_DTRG | gzip > $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz.in_progress; then
				echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
			else
				mv $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.gz
			fi
		else
        		echo "Schema-only backup of $DATABASE"
			if ! pg_dump -s -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" $ARG_ROL $ARG_ECD $ARG_DTRG -f $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.in_progress; then
				echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
			else
				mv $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql.in_progress $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA.sql
			fi
		fi
	done


	###########################
	###### FULL BACKUPS #######
	###########################

	for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
	do
		EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
	done

	FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"

	echo -e "\n\nPerforming full backups"
	echo -e "--------------------------------------------\n"

	for DATABASE in `psql -h "$HOSTNAME" -U "$USERNAME" -At -c "$FULL_BACKUP_QUERY" postgres`
	do
		if [ $ENABLE_PLAIN_BACKUPS = "yes" ]
		then
      if [ $USE_GZIP = "yes" ]
      then
        echo "Plain backup of $DATABASE + gzip"
  			if ! pg_dump -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" $ARG_ROL $ARG_ECD $ARG_DTRG | gzip > $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress; then
  				echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
  			else
  				mv $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE".sql.gz
  			fi
      else
        echo "Plain backup of $DATABASE"
        if ! pg_dump -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" $ARG_ROL $ARG_ECD $ARG_DTRG -f $FINAL_BACKUP_DIR"$DATABASE".sql.in_progress; then
          echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
        else
          mv $FINAL_BACKUP_DIR"$DATABASE".sql.in_progress $FINAL_BACKUP_DIR"$DATABASE".sql
        fi
      fi
		fi

		if [ $ENABLE_CUSTOM_BACKUPS = "yes" ]
		then
			echo "Custom backup of $DATABASE"

			if ! pg_dump -Fc -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" $ARG_ROL $ARG_ECD $ARG_DTRG -f $FINAL_BACKUP_DIR"$DATABASE".custom.sql.in_progress; then
				echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE"
			else
				mv $FINAL_BACKUP_DIR"$DATABASE".custom.sql.in_progress $FINAL_BACKUP_DIR"$DATABASE".custom.sql
			fi
		fi

	done

	echo -e "\nAll database backups complete!"
}

# HOURLY BACKUPS

# Delete old hourly backups
find $BACKUP_DIR -maxdepth 1 -mtime +1 -name "*-hourly" -exec rm -rf '{}' ';'

perform_backups "-hourly"

TEST_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`-*"
for FOUND_DIR in $TEST_DIR
do
  if [ -d $FOUND_DIR ]; then
    echo -e "\n\nSkip long term backups"
    exit 0;
  fi
done

# MONTHLY BACKUPS

DAY_OF_MONTH=`date +%d`

if [ $DAY_OF_MONTH -eq 1 ];
then
	# Delete all expired monthly directories
	find $BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'

	perform_backups "-monthly"

	exit 0;
fi

# WEEKLY BACKUPS

DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`

if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ];
then
	# Delete all expired weekly directories
	find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'

	perform_backups "-weekly"

	exit 0;
fi

# DAILY BACKUPS

# Delete daily backups 7 days old or more
find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'

perform_backups "-daily"
