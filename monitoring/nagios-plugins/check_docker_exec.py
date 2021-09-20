#!/usr/bin/python3

import sys, docker, getopt

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def usage():
	print(f'USAGE: {sys.argv[0]} -n [container_name] -c [command to exec] -t [type of check] -a [check arguments]')
	sys.exit(UNKNOWN)

def main(args):
	client = docker.from_env()
	container_status = {}
	try:
		opts = getopt.getopt(args, 'n:c:t:a:', ['name=', 'cmd=', 'type=', 'args='])[0]
	except:
		usage()

	name = None
	cmd = None
	check_type = None
	check_args = []
	for opt, arg in opts:
		if opt in ('-n', '--name'):
			name = arg
		elif opt in ('-c', '--cmd'):
			cmd = arg
		elif opt in ('-t', '--type'):
			check_type = arg
		elif opt in ('-a', '--args'):
			check_args = arg.split(',')
		else:
			usage()
	if name is None or cmd is None or check_type is None or len(check_args) == 0:
		usage()

	# parse input limits
	try:
		name = str(name)
		cmd = str(cmd)
		check_type = str(check_type)
	except ValueError:
		usage()

	for container in client.containers.list():
		if container.name == name:
			exec_retcode, exec_output = container.exec_run(cmd, tty=True)
			break

	ret_code = OK
	ret_msg = ''
	service_status = {}
	if check_type == 'supervisor':
		if exec_retcode != 0:
			ret_code = CRITICAL
			ret_msg = f'docker exec {cmd} returned nonzero code {exec_retcode}'
		else:
			for line in exec_output.decode().split('\n'):
				if len(line.split()) > 1:
					service_status[line.split()[0]] = line.split()[1]
			for service in check_args:
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
