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

def get_nodes_cpu():
    get_nodes = "/usr/bin/sudo /usr/bin/pvesh get /nodes/ --output-format=json"
    p = subprocess.Popen(get_nodes.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output, err = p.communicate()
    if p.returncode == 0:
        n = output.decode('utf-8').strip()
        n = json.loads(output)
        n = {c['node']: c['maxcpu'] for c in n if c['status'] == 'online'}
        return n
    else:
        return None

def get_nodes_disk():
    get_nodes = "/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=node --output-format=json"
    resources = json.loads(subprocess.check_output(get_nodes.split(), universal_newlines=True))
    get_vms = "/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=vm --output-format=json"
    vms = json.loads(subprocess.check_output(get_vms.split(), universal_newlines=True))
    n = {}
    for node in resources:
        nodename = node['node']
        get_disks = f"/usr/bin/sudo /usr/bin/pvesh get /nodes/{nodename}/disks/list --output-format=json"
        disks = json.loads(subprocess.check_output(get_disks.split(), universal_newlines=True))
        disk_count = 0
        for d in disks:
            if d['size'] > 1000000000000:
                disk_count += 1
        vm_count = len([x for x in vms if x['node'] == nodename])
        try:
            n[nodename] = vm_count/disk_count
        except:
            n[nodename] = 0
    return n

def get_vcpu(node):
    get_vcpu = "/usr/bin/sudo /usr/bin/pvesh get /nodes/" + node + "/qemu --output-format=json"
    p = subprocess.Popen(get_vcpu.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output, err = p.communicate()
    if p.returncode == 0:
        j = output.decode('utf-8').strip()
        j = json.loads(output)
        j = sum(c['cpus'] for c in j if (c['status'] == 'running'))
    else:
        j = 0
    return int(j)

def main(exit):
    try:
        get_n = get_nodes_cpu()
        cpu = sum(get_n.values())
        vcpu = 0
        vcpu_node = {}
        for node in get_n:
            vcpu += get_vcpu(node)
            vcpu_node.update({node: ( get_vcpu(node) / get_n[node] )})
        result_cpu = ' '.join(str(key) + '=' + str(f'{value:.2f}') + ';;;' for key, value in vcpu_node.items())
        agg = ( vcpu / cpu )
        get_nd = get_nodes_disk()
        result_disk = ' '.join(f'disk_{str(key)}=' + str(f'{value:.2f}') + ';;;' for key, value in get_nd.items())
        disk_agg = sum(get_nd.values())/len(get_nd)
        if agg < args.warn:
            print(f'OK: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return OK
        if agg >= args.warn and agg <= args.crit:
            print(f'WARNING: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return WARNING
        else:
            print(f'CRITICAL: Cluster cpu agg is {agg:.2f} vcpu({vcpu})/cpu({cpu}) | cpuagg={agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return CRITICAL
    except BaseException as error:
        print(f"{error}")
        return UNKNOWN

if __name__ == '__main__':
    sys.exit(main(exit))
