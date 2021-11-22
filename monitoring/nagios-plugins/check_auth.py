#!/usr/bin/env python3

from argparse import ArgumentParser
from ftplib import FTP, FTP_TLS
from imaplib import IMAP4, IMAP4_SSL
from poplib import POP3, POP3_SSL
from smtplib import SMTP, SMTP_SSL
import socket
import sys
import yaml

socket.setdefaulttimeout(3.0)
pass_file = '/root/pass.yaml'

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

parser = ArgumentParser(description='Check exim queue on docker container.')
parser.add_argument('--service', '-s', default='ftp',
                    required=True,
                    help='[ftp|ftps|imap|imaps|pop3|pop3s|smpt|smtps]')
parser.add_argument('--hostname', '-H', default='127.0.0.1', required=False)
args = parser.parse_args()

try:
  p_file = yaml.load(open(pass_file), Loader=yaml.BaseLoader)
except:
  print(f'Password file not found {pass_file}')
  sys.exit(UNKNOWN)

def ftp(exit):
  try:
    f = FTP(args.hostname)
    f.login(user = p_file.get('f_user'), passwd = p_file.get('f_pass'))
    f.quit()
    print(f'OK: FTP login successful')
    return OK
  except:
    print(f'WARNING: FTP service was not authorized')
    return CRITICAL

def ftps(exit):
  try:
    f = FTP_TLS(args.hostname)
    f.login(user = p_file.get('f_user'), passwd = p_file.get('f_pass'))
    f.quit()
    print(f'OK: FTPs login successful')
    return OK
  except:
    print(f'WARNING: FTPs service was not authorized')
    return CRITICAL

def imap(exit):
  try:
    i = IMAP4(args.hostname)
    i.login(p_file.get('e_user'), p_file.get('e_pass'))
    i.logout()
    print(f'OK: IMAP login successful')
    return OK
  except:
    print(f'WARNING: IMAP service was not authorized')
    return CRITICAL

def imaps(exit):
  try:
    i = IMAP4_SSL(args.hostname)
    i.login(p_file.get('e_user'), p_file.get('e_pass'))
    i.logout()
    print(f'OK: IMAPs login successful')
    return OK
  except:
    print(f'WARNING: IMAPs service was not authorized')
    return CRITICAL

def pop3(exit):
  try:
    p = POP3(args.hostname)
    p.user(p_file.get('e_user'))
    p.pass_(p_file.get('e_pass'))
    p.quit()
    print(f'OK: POP3 login successful')
    return OK
  except:
    print(f'WARNING: POP3 service was not authorized')
    return CRITICAL

def pop3s(exit):
  try:
    p = POP3_SSL(args.hostname)
    p.user(p_file.get('e_user'))
    p.pass_(p_file.get('e_pass'))
    p.quit()
    print(f'OK: POP3s login successful')
    return OK
  except:
    print(f'WARNING: POP3s service was not authorized')
    return CRITICAL

def smtp(exit):
  try:
    s = SMTP(args.hostname)
    s.login(p_file.get('e_user'), p_file.get('e_pass'))
    s.quit()
    print(f'OK: SMTP login successful')
    return OK
  except:
    print(f'WARNING: SMTP service was not authorized')
    return CRITICAL

def smtps(exit):
  try:
    s = SMTP_SSL(args.hostname)
    s.login(p_file.get('e_user'), p_file.get('e_pass'))
    s.quit()
    print(f'OK: SMTPs login successful')
    return OK
  except:
    print(f'WARNING: SMTPs service was not authorized')
    return CRITICAL

if __name__ == '__main__':
  if args.service == 'ftp':
    sys.exit(ftp(exit))
  elif args.service == 'ftps':
    sys.exit(ftps(exit))
  elif args.service == 'imap':
    sys.exit(imap(exit))
  elif args.service == 'imaps':
    sys.exit(imaps(exit))
  elif args.service == 'pop3':
    sys.exit(pop3(exit))
  elif args.service == 'pop3s':
    sys.exit(pop3s(exit))
  elif args.service == 'smtp':
    sys.exit(smtp(exit))
  elif args.service == 'smtps':
    sys.exit(smtps(exit))
  else:
    print(f'{args.service} service not found')
    sys.exit(UNKNOWN)
