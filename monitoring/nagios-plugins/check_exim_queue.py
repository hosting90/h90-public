#!/usr/bin/env python3

import re
import sys
from argparse import ArgumentParser
from subprocess import Popen, PIPE

parser = ArgumentParser(description='Check exim queue on docker container.')
parser.add_argument('--container', '-cont', default='c-email', help='Default c-email')
parser.add_argument('--warn', '-w', default=350, help='Default 350', type=int)
parser.add_argument('--crit', '-c', default=550, help='Default 550', type=int)
args = parser.parse_args()

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def main(exit):
  try:
    p = Popen(
      ['/usr/bin/sudo', 'docker', 'exec', '-u', 'root', '-i', args.container, 'exim', '-bpc'],
      stdout=PIPE,
      stderr=PIPE
    )
    for line in p.stderr.readlines():
      print('UNKNOWN:', line.decode('utf-8'), end='')
      return UNKNOWN
  except Exception as err:
    print('UNKNOWN:', f'{err}')
    return UNKNOWN

  for line in p.stdout.readlines():
    queue = line.decode('utf-8').strip()
    if int(queue) <= args.warn:
      print(f'OK: exim_queue is {queue} | queue={queue};{args.warn};{args.crit}')
      return OK
    elif int(queue) >= args.warn and queue <= args.crit:
      print(f'WARNING: exim_queue is {queue} | queue={queue};{args.warn};{args.crit}')
      return WARNING
    else:
      print(f'CRITICAL: exim_queue is {queue} | queue={queue};{args.warn};{args.crit}')
      return CRITICAL

if __name__ == '__main__':
  sys.exit(main(exit))