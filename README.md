AUTO_PG_BACKUP_SCRIPT
======================
주기적인 postreSQL 백업을 위한 스크립트

https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux 스크립트에 시간 단위 백업 동작 및 몇 가지 옵션을 추가함

### 추가된 사항
시간 단위로 백업을 함. "날짜H시간-hourly" 형식의 폴더를 백업 디렉토리에 생성후 백업파일 생성하도록 되어 있음

* 매 시간 단위의 폴더들이 생성되며, 하루 단위로 오래된 백업은 삭제함

**PGPASSWORD:** localhost가 아닌 외부 서버 백업할 경우를 위해 패스워드 입력란을 추가함
**USE_GZIP:** 백업 파일을 gz압축을 할지 안 할지 선택
**ENCODING:** pg_dump 인코딩 옵션
**DISABLE_TRIGGERS:** pg_dump의 --disable-triggers 옵션

### 사용법

백업할 서버에 맞게 .config파일을 작성

```shell
##############################
## POSTGRESQL BACKUP CONFIG ##
##############################

# Optional system user to run backups as.  If the user the script is running as doesn't match this
# the script terminates.  Leave blank to skip check.
BACKUP_USER=

# Optional hostname to adhere to pg_hba policies.  Will default to "localhost" if none specified.
HOSTNAME="192.168.1.147"

# Optional username to connect to database as.  Will default to "postgres" if none specified.
USERNAME=

# postgres password
PGPASSWORD="crossing"

# This dir will be created if it doesn't exist.  This must be writable by the user the script is
# running as.
BACKUP_DIR="/home/pi/pgs/"

# List of strings to match against in database name, separated by space or comma, for which we only
# wish to keep a backup of the schema, not the data. Any database names which contain any of these
# values will be considered candidates. (e.g. "system_log" will match "dev_system_log_2010-01")
SCHEMA_ONLY_LIST=""

# Set role name
ROLE="shcm"

# Will produce a custom-format backup if set to "yes"
ENABLE_CUSTOM_BACKUPS=yes

# Will produce a plain-format backup if set to "yes"
ENABLE_PLAIN_BACKUPS=yes

# Will produce sql file containing the cluster globals, like users and passwords, if set to "yes"
ENABLE_GLOBALS_BACKUPS=yes

####### Other options #######

# Compress using gzip
USE_GZIP=yes

# Set Encoding
ENCODING="UTF8"

# Disable triggers
DISABLE_TRIGGERS=yes

#############################

#### SETTINGS FOR ROTATED BACKUPS ####

# Which day to take the weekly backup from (1-7 = Monday-Sunday)
DAY_OF_WEEK_TO_KEEP=2

# Number of days to keep daily backups
DAYS_TO_KEEP=7

# How many weeks to keep weekly backups
WEEKS_TO_KEEP=5

######################################
```
config파일과 백업 스크립트를 /etc/crontab(리눅스 기준 경로)에 등록

```shell
# m h dom mon dow user	command
17 *	* * *	root    cd / && run-parts --report /etc/cron.hourly
25 6	* * *	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
47 6	* * 7	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
52 6	1 * *	root	test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
# every 10min
*/10 *	* * *	root	/home/pi/sh/pgs_backup_rotate.sh
# every 1hour at ##:44
44 *	* * *	root	/home/pi/sh/pgs_backup_rotate.sh -c /home/pi/sh/pgs_backup_2.config
#
```