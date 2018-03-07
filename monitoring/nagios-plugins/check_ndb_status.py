#!/usr/bin/python

import sys, pexpect, re

OK = 0
CRITICAL = 2
UNKNOWN = 3

disconnected_servers = []

session = pexpect.spawn('ndb_mgm')

try:
	session.expect_exact('ndb_mgm>')

	session.sendline('show')
	session.expect('ndb_mgm>')

	show = session.before
	ids = re.findall('id=\d', show)

	for i in ids:
		i = i[3:]
		session.sendline(i + ' status')
		session.expect('ndb_mgm>')
		node_status = session.before

		if (len(re.findall(': connected', node_status)) == 0 and len(re.findall(': started', node_status)) == 0):
			disconnected_servers.append(i)

except pexpect.EOF:
	print 'EOF:' + session.before
	sys.exit(UNKNOWN)

except pexpect.TIMEOUT:
	print session.before
	sys.exit(CRITICAL)

if len(disconnected_servers) > 0:
	print 'disconected nodes: ' + str(disconnected_servers)
	sys.exit(CRITICAL)
else:
	print 'all servers are connected'
	sys.exit(OK)