#!/bin/bash
#
#   Skript for detailed monitoring of wireguard
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       31.08.2026 - First version

#   variables
tmp_file="/tmp/check_wireguard_${1}.tmp";  #  $1 used for specified check
activity_file="/tmp/check_wireguard_activity.tmp";
wireguard_clients_folder="/etc/wireguard/clients/";
wireguard_minutes_handshake=2;
output="Wireguard ${1}";

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

function check_running() {
    #   inputs values
    #   $1  string  service

    systemctl is-active ${1} >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        return 1;
    else
        return 0;
    fi;
}

function read_values() {
    #   inputs values
    #   $1  string  command (check|list-backups...)

    local cmd="${1}";

    case "${cmd}" in
        "activity")
            wg show interfaces | tr ' ' '\n' > ${tmp_file}_nic;
            if [[ $? -gt 0 ]];
            then
                error "Error while checking wireguard's NICs!";
            fi;

            for nic in $(wg show interfaces); do 
                wg show ${nic} > ${tmp_file}_nic;
                if [[ $? -gt 0 ]];
                then
                    error "Error while showing details about a wg show ${nic}!";
                fi;
            done;

            ls ${wireguard_clients_folder} | awk -F ".conf" '{print $1}' > ${tmp_file}_profiles;
            if [[ $? -gt 0 ]];
            then
                error "Error while checking profiles for wireguard!";
            fi;

            for profile in $(ls ${wireguard_clients_folder} | awk -F ".conf" '{print $1}'); do
                profile_addr=$(cat ${wireguard_clients_folder}${profile}.conf | grep -i "Address" | awk -F " = " '{print $2}' | awk -F "/" '{print $1}');
                profile_interface=$(ip -br addr show | grep "$(echo ${profile_addr} | awk -F "." '{print $1"."$2"."$3}')" | awk '{print $1}');
                profile_last_handshake=$(wg show ${profile_interface} dump | grep "${profile_addr}/32" | awk '{print $5}');

                if [[ "${profile_last_handshake}" -eq 0 ]];
                then
                    profile_state="offline";
                else
                    local tmp_epoch=$(date +%s);
                    if [[ "$(( (tmp_epoch - profile_last_handshake) / 60 ))" -gt ${wireguard_minutes_handshake} ]];
                    then
                        profile_state="offline";
                    else
                        profile_state="online";
                    fi;
                fi;

                profile_rx=$(wg show ${profile_interface} dump | grep "${profile_addr}/32" | awk '{printf "%.2f\n", $6/1024/1024}');
                profile_tx=$(wg show ${profile_interface} dump | grep "${profile_addr}/32" | awk '{printf "%.2f\n", $7/1024/1024}');

                echo -e "{\n\t\"name\": \"${profile}\",\n\t\"address\": \"${profile_addr}\",\n\t\"interface\": \"${profile_interface}\",\n\t\"last_handshake\": \"${profile_last_handshake}\",\n\t\"state\": \"${profile_state}\",\n\t\"received\": \"${profile_rx}\",\n\t\"transfer\": \"${profile_tx}\"\n}" > ${tmp_file}_${profile};
                if [[ $? -gt 0 ]];
                then
                    error "Error while create a VPN profile tmp file [${tmp_file}]_${profile}!";
                fi;
            done;
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in wg-quick@$(wg | grep -i interface | awk -F ": " '{print $2}'); do
            if check_running "${service}";
            then
                result="${result} ${service}=1;0;0;0;1";
            else
                end_code=1;
                result="${result} ${service}=0;0;0;0;1";
            fi;
        done;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            warning "${output} PROBLEM | ${result}"
        fi;
    ;;

    "activity")
        info_text="${1} Peers (all/online/offline)";
        result="";
        end_code=0;

        read_values "${1}";
        
        counter_clients_all=$(cat ${tmp_file}_profiles | wc -l);
        counter_clients_online=0;
        counter_clients_offline=0;

        for vpn_profile in $(cat ${tmp_file}_profiles); do
            if [[ "$(cat ${activity_file}_${vpn_profile} | jq -r '.state')" == "online" ]];
            then
                ((counter_clients_online++));
            else
                ((counter_clients_offline++));
            fi;
        done;
        
        info_text="${info_text} (${counter_clients_all}/${counter_clients_online}/${counter_clients_offline})";

        result="${result} counter_clients_all=${counter_all};;;; counter_clients_online=${counter_clients_online};;;0;${counter_clients_all} counter_clients_offline=${counter_clients_offline};;;0;${counter_clients_all}";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;

    "clients_traffic")
        info_text="${1} Clients traffic [MiB]";
        result="";
        end_code=0;

        for vpn_profile in $(cat ${activity_file}_profiles); do
            profile_incoming="$(cat ${activity_file}_${vpn_profile} | jq -r '.received')";
            profile_outgoing="$(cat ${activity_file}_${vpn_profile} | jq -r '.transfer')";
            result="${result} profile_${vpn_profile}_incoming=${profile_incoming};;;; profile_${vpn_profile}_outgoing=${profile_outgoing};;;;";
        done;

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
