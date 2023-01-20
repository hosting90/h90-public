#!/usr/bin/env python3

import sys
import re
import subprocess
from argparse import ArgumentParser
import json
import socket
socket.setdefaulttimeout(3)

parser = ArgumentParser(description='CPU aggregation')
parser.add_argument('--warn', '-w', default=20, help='Default 20', type=int)
parser.add_argument('--crit', '-c', default=30, help='Default 30', type=int)
args = parser.parse_args()

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def get_vcpu():
    node = str(socket.gethostname().split('.', 1)[0])
    get_vcpu = "/usr/bin/sudo /usr/bin/pvesh get /nodes/" + node + "/qemu --output-format=json"
    p = subprocess.Popen(get_vcpu.split(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output, err = p.communicate()
    if output:
        j = output.decode('utf-8').strip()
        j = json.loads(output)
        j = sum(c['cpus'] for c in j)
    return int(j)

def get_cpu():
    with open('/proc/cpuinfo', 'r') as f:
        c = f.read()
        c = len(re.findall('processor', c))
    return int(c)

def main(exit):
    try:
        agg = ( (get_vcpu()) / (get_cpu()) )
        if agg < args.warn:
            print(f'OK: cpu agg is {agg:.2f} | cpuagg={agg:.2f};{args.warn};{args.crit}')
            return OK
        if agg >= args.warn and agg <= args.crit:
            print(f'WARNING: cpu agg is {agg:.2f} | cpuagg={agg:.2f};{args.warn};{args.crit}')
            return WARNING
        else:
            print(f'CRITICAL: cpu agg is {agg:.2f} | cpuagg={agg:.2f};{args.warn};{args.crit}')
            return CRITICAL
    except BaseException as error:
        print(f"{error}")
        return UNKNOWN

if __name__ == '__main__':
    sys.exit(main(exit))
