#!/usr/bin/env python3
import sys
import subprocess
from argparse import ArgumentParser
import json

parser = ArgumentParser(description='CPU aggregation')
parser.add_argument('--warn', '-w', default=20, help='Default 20', type=int)
parser.add_argument('--crit', '-c', default=30, help='Default 30', type=int)
args = parser.parse_args()

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def get_nodes():
    get_nodes = "/usr/bin/sudo /usr/bin/pvesh get /nodes/ --output-format=json"
    p = subprocess.Popen(get_nodes.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output, err = p.communicate()
    if output:
        n = output.decode('utf-8').strip()
        n = json.loads(output)
        n = {c['node']: c['maxcpu'] for c in n}
    return n

def get_vcpu(node):
    get_vcpu = "/usr/bin/sudo /usr/bin/pvesh get /nodes/" + node + "/qemu --output-format=json"
    p = subprocess.Popen(get_vcpu.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output, err = p.communicate()
    if output:
        j = output.decode('utf-8').strip()
        j = json.loads(output)
        j = sum(c['cpus'] for c in j if (c['status'] == 'running'))
    return int(j)

def main(exit):
    try:
        get_n = get_nodes()
        cpu = sum(get_n.values())
        vcpu = 0
        vcpu_node = {}
        for node in get_n:
            vcpu += get_vcpu(node)
            vcpu_node.update({node: ( get_vcpu(node) / get_n[node] )})
        result = ' '.join(str(key) + '=' + str(f'{value:.2f}') + ';;;' for key, value in vcpu_node.items())
        agg = ( vcpu / cpu )
        if agg < args.warn:
            print(f'OK: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} {result}')
            return OK
        if agg >= args.warn and agg <= args.crit:
            print(f'WARNING: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} {result}')
            return WARNING
        else:
            print(f'CRITICAL: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} {result}')
            return CRITICAL
    except BaseException as error:
        print(f"{error}")
        return UNKNOWN

if __name__ == '__main__':
    sys.exit(main(exit))
