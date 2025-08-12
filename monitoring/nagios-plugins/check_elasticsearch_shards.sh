#!/bin/bash
#
#   Skript for a check EL shards
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
ES_URL="https://localhost:9200";
ES_USER="${1}";
ES_PASSWORD="${2}";

#   functions
function check_input() {
    if [[ -z "${ES_USER}" || -z "${ES_PASSWORD}" ]];
    then
        echo -e "Missing params!\nUsage: ${0} <es_user> <es_password>";
        exit 1;
    fi;
}

function check_shards() {
    #   no inputs available

    total_shards=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "${ES_URL}/_cat/shards" | wc -l);
    shard_limit=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "${ES_URL}/_cluster/settings?include_defaults=true" | jq -r '.persistent.cluster.max_shards_per_node');
    node_count=$(curl -s -k -u "${ES_USER}:${ES_PASSWORD}" "${ES_URL}/_cat/nodes?h=name" | wc -l);
    cluster_limit=$((shard_limit * node_count));
    percent_usage=$((total_shards * 100 / cluster_limit));

    #   format 
    #   label=value[UOM];warn;crit;min;max

    echo "Elasticsearch shards: ${total_shards}/${cluster_limit} used (${percent_usage}%) | shards_total=${total_shards};$((cluster_limit*80/100));$((cluster_limit*90/100));0;${cluster_limit} shards_limit=${cluster_limit};;;0 shards_percent=${percent_usage};80;90;0;100";

    
    exit 0;
}

#   script body
check_input;
check_shards;

exit;
