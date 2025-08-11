#!/bin/bash
#
#   Skript for a SQL Injection check
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
LOCKFILE="/tmp/sql_injection.lock";
TMP_FILE="/tmp/sql_injection.sql";
SLEEP=10;
LOOP=3;
PASSWORD=${1};

#   functions
function check_input() {
    if [[ -z "${PASSWORD}" ]];
    then
        echo -e "Missing params!\nUsage: ${0} <mysql_password>";
        exit 1;
    fi;
}

function check_lock() {
    if [[ -f "${LOCKFILE}" ]];
    then
        PID=$(cat ${LOCKFILE});
        if ps -p ${PID} > /dev/null 2>&1;
        then
            echo -e "Script is already running on PID [${PID}]";
            exit 2;
        else
            #   lockfile found, but ps doesn't use this PID
            #       so we unset the lockfile
            rm -f "${LOCKFILE}";
        fi;
    fi;
}

function write_pid() {
    echo $$ > ${LOCKFILE};
    if [[ $? -gt 0 ]];
    then
        echo -e "Failed to write a lockfile!";
        exit 3;
    fi;
}

function check_injections() {
    mysql -u nagios -p${PASSWORD} -e "SHOW FULL PROCESSLIST" | grep -Ei 'union select|sleep|benchmark|or 1=1|--|information_schema|char\(|0x' > ${TMP_FILE};

    if [[ $(cat ${TMP_FILE} | wc -l) -gt 0 ]];
    then
        echo -e "SQL Injection found - details in file [${TMP_FILE}_found]!";
        cp ${TMP_FILE} ${TMP_FILE}_found;
        exit 4;
    else
        echo -e "No SQL INJECTION found.";
        exit 0;
    fi;
}

#   script body
check_input;
check_lock;
write_pid;

for i in $(seq 0 1 ${LOOP}); do
    check_injections;
    sleep ${SLEEP};
done;

#   trap to remove lockfile on exit
trap "rm -v ${LOCKFILE}" EXIT;

exit;
