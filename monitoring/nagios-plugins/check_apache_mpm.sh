#!/bin/bash
#
#   Skript for a Apache MPM
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
APACHE_STATUS_PAGE="http://localhost/server-status?auto";
APACHE_MPM="";
APACHE_MAX_SERVERS="";
APACHE_ACTUALL_SERVERS="";

#   functions
function check_input() {
    #   check which MPM server use
    APACHE_MPM=$(apachectl -V | grep -i "mpm" | awk -F ":" '{print $2}' | xargs);

    #   check apache actuall servers
    if [[ $(pgrep apache | wc -l) -eq 0 && $(pgrep httpd | wc -l) -eq 0 ]];
    then
        APACHE_ACTUALL_SERVERS=0;
    else
        if [[ "$(pgrep apache | wc -l)" -eq 0 ]];
        then
            APACHE_ACTUALL_SERVERS=$(pgrep httpd | wc -l);
        else
            APACHE_ACTUALL_SERVERS=$(pgrep apache | wc -l);
        fi;
    fi

    case "${APACHE_MPM}" in
        "prefork")
            for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
                if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
                then
                    for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do 
                        if [[ ${file} =~ \.conf$|\.ini$ ]];
                        then
                            APACHE_MAX_SERVERS=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ServerLimit" | awk '{print $2}');
                        fi;

                        if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                        then
                            break;
                        fi;
                    done;

                    if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                    then
                        break;
                    fi;
                fi;
            done            
        ;;

        "worker")
            for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
                if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
                then
                    for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do 
                        if [[ ${file} =~ \.conf$|\.ini$ ]];
                        then
                            APACHE_MAX_SERVERS=$(cat ${file} | grep -A 8 "${APACHE_MPM}" | grep -i "ServerLimit" | awk '{print $2}');
                        fi;

                        if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                        then
                            break;
                        fi;
                    done;

                    if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                    then
                        break;
                    fi;
                fi;
            done        
        ;;
        
        "event")
            for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
                if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
                then
                    for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do 
                        if [[ ${file} =~ \.conf$|\.ini$ ]];
                        then
                            APACHE_MAX_SERVERS=$(cat ${file} | grep -A 8 "${APACHE_MPM}" | grep -i "ServerLimit" | awk '{print $2}');
                        fi;

                        if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                        then
                            break;
                        fi;
                    done;

                    if [[ ! -z ${APACHE_MAX_SERVERS} ]];
                    then
                        break;
                    fi;
                fi;
            done           
        ;;
    esac;

    #   if isn't defined - default system value
    if [[ -z "${APACHE_MAX_SERVERS}" ]];
    then
        case ${APACHE_MPM} in
            "prefork")
                APACHE_MAX_SERVERS=256;
            ;;

            "worker")
                APACHE_MAX_SERVERS=16;
            ;;

            "event")
                APACHE_MAX_SERVERS=16;
            ;;
        esac;
    fi;

    #   calculating values
    percent_usage=$((APACHE_ACTUALL_SERVERS * 100 / APACHE_MAX_SERVERS));

    #   return values
    echo "Apache MPM ${APACHE_MPM}: ${APACHE_ACTUALL_SERVERS}/${APACHE_MAX_SERVERS} used (${percent_usage}%) | apache_servers=${APACHE_ACTUALL_SERVERS};$((APACHE_MAX_SERVERS*80/100));$((APACHE_MAX_SERVERS*90/100));0;${APACHE_MAX_SERVERS} max_servers=${APACHE_MAX_SERVERS};;;0 servers_percent=${percent_usage};80;90;0;100";
}

#   script body
check_input;

exit;
