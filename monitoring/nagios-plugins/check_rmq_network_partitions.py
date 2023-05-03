#!/usr/bin/env python3

import json
from subprocess import Popen, PIPE
import sys

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3
CMD = "/usr/bin/sudo docker exec -u root -i c-rmq rabbitmqctl cluster_status --formatter json"

def main(exit):
    try:
        p = Popen(CMD.split(), stdout=PIPE, stderr=PIPE)
        for line in p.stderr.readlines():
            print('UNKNOWN:', line.decode('utf-8'), end='')
            return UNKNOWN
    except Exception as err:
        print('UNKNOWN:', f'{err}')
        return UNKNOWN

    data = json.load(p.stdout)
    partitions = data.get('partitions', {})
    running_nodes = data.get('running_nodes', {})
    if len(partitions) == 0 and len(running_nodes) == 3:
        print(f"partitions: {json.dumps(partitions, indent=4)}")
        print(f"running_nodes: {json.dumps(running_nodes, indent=4)}")
        return OK
    else:
        print(f"partitions: {json.dumps(partitions, indent=4)}")
        print(f"running_nodes: {json.dumps(running_nodes, indent=4)}")
        return CRITICAL

if __name__ == '__main__':
  sys.exit(main(exit))