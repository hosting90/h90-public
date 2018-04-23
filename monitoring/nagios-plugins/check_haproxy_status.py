#!/usr/bin/python

from __future__ import division
import sys, getopt
from haproxyadmin import haproxy

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def count_backend(criticals, backend_name):
	count = 0
	for server in criticals:
		if server[0] == backend_name:
			count = count + 1
	return count

def main(args):
	critical_level = 0.4 #default percentage of offline servers for critical
	haproxy_socket = '/var/run/haproxy.sock'
	critical_frontends = []
	critical_backends = []
	critical_servers = []

	try:
		opts, args = getopt.getopt(sys.argv[1:], "c:", ["climit="])
		for opt, arg in opts:
			if opt in ('-c', '--climit'):
				critical_level = float(arg)
			if opt in ('-s', '--socket'):
				haproxy_socket = arg

	except:
		print 'Incorrect arguments.'
		return UNKNOWN

	if critical_level > 1:
		critical_level = critical_level / 100


	hap = haproxy.HAProxy(socket_file=haproxy_socket)
	frontend_list = hap.frontends()
	backend_list = hap.backends()

	for frontend in frontend_list:
		if frontend.status != 'OPEN':
			critical_frontends.append((frontend.name, frontend.status))

	for backend in backend_list:
		if backend.status != 'UP':
			critical_backends.append((backend.name, backend.status))
		else:
			server_list = backend.servers()
			if len(server_list) == 0:
				continue
			for server in server_list:
				if server.status != 'UP' and server.status != 'no check':
					critical_servers.append((backend.name, server.name, server.status))

			if (count_backend(critical_servers, backend.name) / len(server_list)) >=critical_level:
				critical_backends.append((backend.name, backend.status))

	message = []

	for frontend in critical_frontends:
		message.append( frontend[0] + ' frontend is in ' + frontend[1] + ' state.')

	for backend in critical_backends:
		if backend[1] == 'UP':
			message.append( backend[0] + ' backend has >' + str(critical_level * 100) + '\% of servers down.')
		else:
			message.append( backend[0] + ' backend is in ' + backend[1] ' state.')

	if len(message) == 0:
		if len(critical_servers) == 0:
			print 'All frontends, backends, and attached servers are running and enabled.'
			return OK
		else:
			for server in critical_servers:
				message.append(server[1] + ' server of ' + server[0] + ' backend is in ' + server[2] + ' state.')
			
			print '; '.join(message)
			return WARNING

	else:
		print '; '.join(message)
		return CRITICAL

if __name__ == '__main__':
	sys.exit(main(sys.argv))