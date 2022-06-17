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
  print(f'| ', end="")
  for item in p.stdout.readlines():
      data_out = item.split()
      NAME = (data_out[0]).decode("utf-8")
      USEDSNAP = (data_out[3]).decode("utf-8")
      USEDDS = (data_out[4]).decode("utf-8")
      print(f'{NAME}={USEDDS}B;;; {NAME}/snap={USEDSNAP}B;;;', end=" ")

if __name__ == '__main__':
  sys.exit(main())
