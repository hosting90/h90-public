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
	critical_frontends = []
	critical_backends = []
	critical_servers = []

	try:
		opts, args = getopt.getopt(sys.argv[1:], "c:", ["climit="])
		for opt, arg in opts:
			if opt in ('-c', '--climit'):
				critical_level = float(arg)

	except:
		print 'wrong arguments'
		return UNKNOWN

	if critical_level > 1:
		critical_level = critical_level / 100


	hap = haproxy.HAProxy(socket_file='/var/run/haproxy.sock')
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
		message.append('frontend ' + frontend[0] + ' has status: ' + frontend[1])

	for backend in critical_backends:
		if backend[1] == 'UP':
			message.append('backend ' + backend[0] + ' has more than ' + str(critical_level * 100) + ' % of servers not up')
		else:
			message.append('backend ' + backend[0] + ' has status ' + backend[1])

	if len(message) == 0:
		if len(critical_servers) == 0:
			print 'all frontends, backends and servers are up and running'
			return OK
		else:
			for server in critical_servers:
				message.append('server ' + server[1] + ' of backend ' + server[0] + ' has status ' + server[2])
			
			print '; '.join(message)
			return WARNING

	else:
		print '; '.join(message)
		return CRITICAL

if __name__ == '__main__':
	sys.exit(main(sys.argv))