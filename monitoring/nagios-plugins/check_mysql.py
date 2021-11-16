#!/usr/bin/env python3

import re
import sys
from subprocess import Popen, PIPE

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def usage():
  print(f'USAGE: {sys.argv[0]} [mysql<version> container name without c-]')
  sys.exit(UNKNOWN)

def main(args):
  try:
    p = Popen(
      ['/usr/bin/sudo', 'docker', 'exec', '-u', 'root', '-i', 'c-' + sys.argv[1], 'mysqladmin', 'ping'],
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
    if re.search(r'alive', line.decode('utf-8')):
      print('OK:', line.decode('utf-8'), end='')
      return OK
    else:
      print('CRITICAL:', line.decode('utf-8'), end='')
      return CRITICAL
  return UNKNOWN

if __name__ == '__main__':
  if len(sys.argv) == 2:
    sys.exit(main(sys.argv[1:]))
  else:
    usage()
    sys.exit(UNKNOWN)