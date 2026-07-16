#!/bin/bash
#
#   Script for individually working with a log file
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       16.07.2026 - Fixed problem with a condition to trigger incident
#       14.07.2026 - First version

#   variables
tmp_file="/tmp/check_log_file.tmp";
tmp_log_file="/tmp/check_log_file_lines.tmp";
log_file="${1}";
last_lines="${2}";
strings_to_check="${3}";
names_of_check="${4}";
output="Log file checker - file ${log_file}";


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

function check() {
    #   no inputs

    if [[ -f "${tmp_file}" ]];
    then
        rm ${tmp_file};
    fi;

    if [[ ! -f "${log_file}" ]];
    then
        error "Log file not found [${log_file}]!";
    fi;

    # define the arrays
    IFS='|' read -ra strings <<< "${strings_to_check}"; 
    if [[ $? -gt 0 ]]; 
    then 
        error "Error while convert string_to_check into array!"; 
    fi; 
    
    IFS='|' read -ra names <<< "${names_of_check}"; 
    if [[ $? -gt 0 ]]; 
    then 
        error "Error while convert names_of_check into array!"; 
    fi;

    # check same number of elements
    if (( ${#strings[@]} != ${#names[@]} ));
    then
        error "Error array have different number of elements!";
    fi;
}

function prepare_outputs() {
    #   no inputs

    tail -n ${last_lines} ${log_file} > ${tmp_log_file};

    for ((i=0; i<${#strings[@]}; i++)); do
        local string_to_search="${strings[i]}";
        local name_of_check="${names[i]}";

        if [[ $(cat ${tmp_log_file} | grep -i "${string_to_search}" | wc -l) -gt 0 ]];
        then
            echo "${name_of_check}" >> ${tmp_file};
            break;
        fi;    
    done;
}

function check_outputs() {
    #   no inputs

    info_text="";
    end_code=0;

    for ((i=0; i<${#strings[@]}; i++)); do
        local string_to_search="${strings[i]}";
        local name_of_check="${names[i]}";    

        if [[ -f "${tmp_file}" ]];
        then
            if [[ $(cat ${tmp_file} | grep "${name_of_check}" | wc -l) -gt 0 ]];
            then
                info_text="${info_text} FOUND in log file [${name_of_check}]!";
                end_code=2;
            fi;
        fi;
    done;        

    case "${end_code}" in
        0)
            output="${output} OK: No problems found.";
        ;;

        1)
            warning "${output} WARNING: ${info_text}";
        ;;

        *)
            error "${output} CRITICAL: ${info_text}";
        ;;
    esac;    

    echo ${output};    
}


#   check body
check;
prepare_outputs;
check_outputs;

exit;
