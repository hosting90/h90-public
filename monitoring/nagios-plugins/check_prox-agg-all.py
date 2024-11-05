#!/usr/bin/env python3
import sys
import subprocess
from argparse import ArgumentParser
import json
from concurrent.futures import ThreadPoolExecutor

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
    p = subprocess.Popen(get_nodes.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, err = p.communicate()
    if p.returncode == 0:
        nodes = json.loads(output.decode('utf-8').strip())
        return {c['node']: c['maxcpu'] for c in nodes if c['status'] == 'online'}
    return None

def get_nodes_disk():
    get_nodes = "/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=node --output-format=json"
    resources = json.loads(subprocess.check_output(get_nodes.split(), universal_newlines=True))
    get_vms = "/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=vm --output-format=json"
    vms = json.loads(subprocess.check_output(get_vms.split(), universal_newlines=True))

    disk_ratios = {node['node']: 0 for node in resources if node['status'] == 'online'}
    for node in resources:
        if node['status'] != 'online':
            continue
        nodename = node['node']
        get_disks = f"/usr/bin/sudo /usr/bin/pvesh get /nodes/{nodename}/disks/list --output-format=json"
        disks = json.loads(subprocess.check_output(get_disks.split(), universal_newlines=True))
        disk_count = sum(1 for d in disks if d['size'] > 1_000_000_000_000)
        vm_count = len([x for x in vms if x['node'] == nodename])
        disk_ratios[nodename] = vm_count / disk_count if disk_count else 0
    return disk_ratios

def get_vcpu(node):
    get_vcpu_cmd = f"/usr/bin/sudo /usr/bin/pvesh get /nodes/{node}/qemu --output-format=json"
    p = subprocess.Popen(get_vcpu_cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, err = p.communicate()
    if p.returncode == 0:
        vms = json.loads(output.decode('utf-8').strip())
        return sum(vm['cpus'] for vm in vms if vm['status'] == 'running')
    return 0

def main():
    try:
        nodes_cpu = get_nodes_cpu()
        if not nodes_cpu:
            print("Error: Could not retrieve CPU information for nodes.")
            return UNKNOWN
        total_cpu = sum(nodes_cpu.values())
        
        # Use ThreadPoolExecutor to parallelize get_vcpu calls for each node
        with ThreadPoolExecutor() as executor:
            vcpu_futures = {node: executor.submit(get_vcpu, node) for node in nodes_cpu.keys()}
        
        # Calculate total vCPU and ratios per node
        vcpu_total = 0
        vcpu_node_ratios = {}
        for node, future in vcpu_futures.items():
            vcpu = future.result()
            vcpu_total += vcpu
            vcpu_node_ratios[node] = vcpu / nodes_cpu[node] if nodes_cpu[node] else 0

        # Calculate aggregated CPU ratio
        cpu_agg = vcpu_total / total_cpu if total_cpu else 0

        # Get disk ratios and aggregate them
        node_disk_ratios = get_nodes_disk()
        disk_agg = sum(node_disk_ratios.values()) / len(node_disk_ratios) if node_disk_ratios else 0

        # Format output for CPU and Disk with consistent ordering
        result_cpu = ' '.join(f"{node}={vcpu_node_ratios[node]:.2f};;;" for node in sorted(vcpu_node_ratios))
        result_disk = ' '.join(f"disk_{node}={node_disk_ratios[node]:.2f};;;" for node in sorted(node_disk_ratios))

        # Determine status based on thresholds
        if cpu_agg < args.warn:
            print(f'OK: Cluster cpu agg is {cpu_agg:.2f} vcpu({vcpu_total})/cpu({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return OK
        elif args.warn <= cpu_agg <= args.crit:
            print(f'WARNING: Cluster cpu agg is {cpu_agg:.2f} vcpu({vcpu_total})/cpu({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return WARNING
        else:
            print(f'CRITICAL: Cluster cpu agg is {cpu_agg:.2f} vcpu({vcpu_total})/cpu({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {result_cpu} {result_disk}')
            return CRITICAL
    except Exception as error:
        print(f"Error: {error}")
        return UNKNOWN

if __name__ == '__main__':
    sys.exit(main())
