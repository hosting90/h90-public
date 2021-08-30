#!/usr/bin/python3

import sys, subprocess, getopt

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def usage():
	print(f'USAGE: {sys.argv[0]} [service1 [service2...]]')
	sys.exit(UNKNOWN)

def main(args):
	service_status = {}
	ret_code = OK
	ret_msg = ''
	supervisorctl_output = subprocess.run(['supervisorctl', 'status'], capture_output=True).stdout.decode().split('\n')
	for line in supervisorctl_output:
		if len(line.split()) > 1:
			service_status[line.split()[0]] = line.split()[1]
	for service in args:
		if service not in service_status:
			ret_code = UNKNOWN
			ret_msg += f'{service} not present in supervisorctl status output!!!\n'
		else:
			if service_status[service] != 'RUNNING':
				if ret_code < CRITICAL:
					ret_code = CRITICAL
				ret_msg += f'{service} is {service_status[service]}!!!\n'

	if ret_msg == '':
		ret_msg = 'All services are running'

	print(ret_msg)
	return ret_code


if __name__ == '__main__':
	sys.exit(main(sys.argv[1:]))
