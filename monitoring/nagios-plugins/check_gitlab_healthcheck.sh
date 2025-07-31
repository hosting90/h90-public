#!/bin/bash
#
#   Skript for a gitlab check
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
DOMAIN="$1";
HASH="$2"

#   functions
function check_input() {
    if [[ -z "${DOMAIN}" || -z "${HASH}" ]];
    then
        echo -e "Missing params!\nUsage: ${0} <domain> <hash>";
        exit 1;
    fi;
}

function check_json() {
    #   two types
    case ${1} in
        "liveness")
            #   the gitlab UI (code 200 form gitlab UI)
            STATUS=$(curl -L -s "https://${DOMAIN}/-/liveness?token=${HASH}" | jq -r '.status');

            if [[ "${STATUS}" == "ok" ]];
            then
                echo -e "OK - liveness status is [${STATUS}]";
                exit 0;
            else
                echo -e "CRITICAL - liveness status is [${STATUS}], expected [OK] - check gitlab UI.";
                exit 2;
            fi;
        ;;

        "readiness")
            #   web front-end (etc. docker)
            STATUS=$(curl -L -s "https://${DOMAIN}/-/liveness?token=${HASH}" | jq -r '.status');

            if [[ "${STATUS}" == "ok" ]];
            then
                echo -e "OK - frontend status is [${STATUS}]";
                exit 0;
            else
                echo -e "CRITICAL - front-end status is [${STATUS}], expected [OK]";
                exit 3;
            fi;            
        ;;

        *)
            echo -e "Unrecognized type - available types [liveness|readiness]!";
            exit 4;
        ;;
    esac;
}

#   script body
check_input;
check_json "liveness";
check_json "readiness"

exit;
