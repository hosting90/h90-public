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

def run_subprocess(command):
    """Helper function to execute a command and parse JSON output."""
    try:
        output = subprocess.check_output(command.split(), universal_newlines=True)
        return json.loads(output)
    except subprocess.CalledProcessError:
        return None

def get_nodes_cpu():
    nodes = run_subprocess("/usr/bin/sudo /usr/bin/pvesh get /nodes/ --output-format=json")
    return {node['node']: node['maxcpu'] for node in nodes if node['status'] == 'online'} if nodes else {}

def get_nodes_disk():
    resources = run_subprocess("/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=node --output-format=json")
    vms = run_subprocess("/usr/bin/sudo /usr/bin/pvesh get /cluster/resources/ --type=vm --output-format=json")
    if not resources or not vms:
        return {}

    node_disk_ratio = {}
    for node in resources:
        if node['status'] != 'online':
            continue
        nodename = node['node']
        disks = run_subprocess(f"/usr/bin/sudo /usr/bin/pvesh get /nodes/{nodename}/disks/list --output-format=json")
        if disks:
            large_disks = sum(1 for disk in disks if disk['size'] > 1_000_000_000_000)
            vm_count = sum(1 for vm in vms if vm['node'] == nodename)
            node_disk_ratio[nodename] = vm_count / large_disks if large_disks else 0
    return node_disk_ratio

def get_vcpu(node):
    vcpus = run_subprocess(f"/usr/bin/sudo /usr/bin/pvesh get /nodes/{node}/qemu --output-format=json")
    return sum(vm['cpus'] for vm in vcpus if vm['status'] == 'running') if vcpus else 0

def main():
    try:
        nodes_cpu = get_nodes_cpu()
        total_cpu = sum(nodes_cpu.values())
        
        # Parallelize fetching of vCPU counts
        with ThreadPoolExecutor() as executor:
            vcpu_counts = {node: executor.submit(get_vcpu, node) for node in nodes_cpu.keys()}
        
        # Calculate vCPU totals and ratios
        total_vcpu = sum(future.result() for future in vcpu_counts.values())
        vcpu_ratios = {node: vcpu_counts[node].result() / nodes_cpu[node] for node in nodes_cpu.keys()}

        cpu_agg = total_vcpu / total_cpu
        node_disk_ratios = get_nodes_disk()
        disk_agg = sum(node_disk_ratios.values()) / len(node_disk_ratios) if node_disk_ratios else 0

        # Format output for CPU and Disk
        cpu_output = ' '.join(f'{node}={ratio:.2f};;;' for node, ratio in vcpu_ratios.items())
        disk_output = ' '.join(f'disk_{node}={ratio:.2f};;;' for node, ratio in node_disk_ratios.items())

        # Determine status based on thresholds
        if cpu_agg < args.warn:
            print(f'OK: Cluster CPU agg is {cpu_agg:.2f} vCPU({total_vcpu})/CPU({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {cpu_output} {disk_output}')
            return OK
        elif args.warn <= cpu_agg <= args.crit:
            print(f'WARNING: Cluster CPU agg is {cpu_agg:.2f} vCPU({total_vcpu})/CPU({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {cpu_output} {disk_output}')
            return WARNING
        else:
            print(f'CRITICAL: Cluster CPU agg is {cpu_agg:.2f} vCPU({total_vcpu})/CPU({total_cpu}) | '
                  f'cpuagg={cpu_agg:.2f};{args.warn};{args.crit} disk_agg={disk_agg:.2f};;; {cpu_output} {disk_output}')
            return CRITICAL
    except Exception as error:
        print(f"Error: {error}")
        return UNKNOWN

if __name__ == '__main__':
    sys.exit(main())
