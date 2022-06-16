#!/usr/bin/env python3

import sys
from subprocess import Popen, PIPE

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def main():
    p = Popen(
      ['zfs', 'list', '-Hpo', 'space'],
      stdout=PIPE,
      stderr=PIPE
    )
    data_out = []
    print(f'Usage: | ', end="")
    for item in p.stdout.readlines():
        data_out = item.split()
        NAME = (data_out[0]).decode()
        USEDSNAP = data_out[3].decode("utf-8")
        USEDDS = data_out[4].decode("utf-8")
        print(f'{NAME}={USEDDS};;; {NAME}/snap={USEDSNAP};;;', end=" ")

if __name__ == '__main__':
  try:
    main()
    sys.exit(OK)
  except:
    sys.exit(UNKNOWN)