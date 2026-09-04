#!/bin/bash
#
#   Skript for detailed monitoring of typesense (in a docker -> combine with a docker_detailed check!)
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       31.08.2026 - First version

#   variables
tmp_file="/tmp/check_typesense_${1}.tmp";  #  $1 used for specified check
output="Typesense ${1}";

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    echo "${1}";
    exit 2;
}

function warning() {
    #   inputs values
    #   $1  string  message
    echo "${1}";
    exit 1;
}

#   script body
case ${1} in 
    "healthcheck")
        info_text="${1} Typesense";
        result="";
        end_code=0;

        if [[ "$(curl -s 127.0.0.1:8108/health | jq '.ok')" == "true" ]];
        then
            info_text="${info_text} Healthy";
            result="typesence_healthcheck=1;0;0;0;1";
        else
            info_text="${info_text} Unhealthy";
            result="typesence_healthcheck=0;0;0;0;1";
            end_code=2;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;
esac;

echo ${output};

exit;
