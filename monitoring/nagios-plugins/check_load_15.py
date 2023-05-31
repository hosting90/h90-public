#!/usr/bin/env python3

import sys
from argparse import ArgumentParser

parser = ArgumentParser(description='Check 15min loadavg.')
parser.add_argument('--warn', '-w', default=100, help='Default 100', type=float)
parser.add_argument('--crit', '-c', default=250, help='Default 250', type=float)
args = parser.parse_args()

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def main(exit):
    try:
        f = open('/proc/loadavg')
        load15 = float(f.read().split()[2])
    except Exception as err:
        print('UNKNOWN:', f'{err}')
        return UNKNOWN
    if args.warn >= args.crit:
        print(f'Mixed values')
        return UNKNOWN
    if load15 <= args.warn:
      print(f'OK: 15min load is {load15} | load={load15};{args.warn};{args.crit}')
      return OK
    elif load15 >= args.warn and load15 <= float(args.crit):
      print(f'WARNING: 15min load is {load15} | load15={load15};{args.warn};{args.crit}')
      return WARNING
    else:
      print(f'CRITICAL: 15min load is {load15} | load15={load15};{args.warn};{args.crit}')
      return CRITICAL

if __name__ == '__main__':
  sys.exit(main(exit))