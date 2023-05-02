#!/usr/bin/python3

import sys, docker, re

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
	unhealthy_containers = []
	ret_code = OK
	ret_msg = ''
	if len(args) == 0:
		args = ['.*']

	for container in client.containers.list(all=True):
		if any(re.fullmatch(arg, container.name) for arg in args):
			container_status[container.name] = container.attrs['State']['Status']
			if 'Health' in container.attrs['State'] and container.attrs['State']['Health']['Status'] != 'healthy':
				unhealthy_containers.append(container.attrs['Name'])
	for container in args:
		if len(container_status) > 0 and not any(re.fullmatch(container, arg) for arg in container_status.keys()):
			ret_code = UNKNOWN
			ret_msg += f'{container} not present in docker container status list {str(container_status)}!!!\n'

	for container in container_status:
		if not re.fullmatch(r'(running)', container_status[container]):
			if ret_code < CRITICAL:
				ret_code = CRITICAL
			ret_msg += f'{container} is {container_status[container]}!!!\n'

	if len(unhealthy_containers) > 0:
		if ret_code < CRITICAL:
			ret_code = CRITICAL
		ret_msg += f'Unhealthy containers present: {unhealthy_containers}\n'
	if ret_msg == '':
		ret_msg = 'All containers are running'

	print(ret_msg)
	return ret_code


if __name__ == '__main__':
	sys.exit(main(sys.argv[1:]))
