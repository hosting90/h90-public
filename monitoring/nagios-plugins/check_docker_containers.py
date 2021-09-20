#!/usr/bin/python3

import sys, docker

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def usage():
	print(f'USAGE: {sys.argv[0]} [container1 [container2...]]')
	sys.exit(UNKNOWN)

def main(args):
	client = docker.from_env()
	container_status = {}
	ret_code = OK
	ret_msg = ''

	for container in client.containers.list():
		if container.name in args:
			container_status[container.name] = container.attrs['State']['Status']
	for container in args:
		if container not in container_status:
			ret_code = UNKNOWN
			ret_msg += f'{container} not present in supervisorctl status output!!!\n'
		else:
			if container_status[container] != 'running':
				if ret_code < CRITICAL:
					ret_code = CRITICAL
				ret_msg += f'{container} is {container_status[container]}!!!\n'

	if ret_msg == '':
		ret_msg = 'All containers are running'

	print(ret_msg)
	return ret_code


if __name__ == '__main__':
	sys.exit(main(sys.argv[1:]))
