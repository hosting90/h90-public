#!/usr/bin/python

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

import sys
PYTHON_MODULES = ['re', 'subprocess']
for module in PYTHON_MODULES:
	try:
		locals()[module] = __import__(str(module))
	except ImportError:
		print "UNKNOWN: cannot load %s module!" % module
		sys.exit(UNKNOWN)

def main(args):
	process = subprocess.Popen(['service','spamassassin','status'], stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	if process.returncode != 0 or stdout.strip() == '':
		print "spamassassin status failed."
		return CRITICAL
	f=open('/etc/redhat-release','r')
	c_version = f.read()
	f.close()
	if re.search('release 6',c_version) != None:
		if re.search('running...',stdout.strip()) == None:
			print "Cannot get spamassassin status"
			return CRITICAL
		else:
			service_status = stdout.strip()
			print service_status
			return OK
	else:
		try:
			service_status = filter(lambda line: re.search(re.compile("Active.*ago"),line), stdout.strip().split('\n'))[0].strip()
		except IndexError:
			print "Cannot get spamassassin active age"
			return CRITICAL
	process = subprocess.Popen(['sudo','spamc','-t','20','-n','20','-K','-U','/var/run/spamassassin/spamd.sock'], stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	if process.returncode != 0 or stdout.strip() == '':
		print "spamassassin keepalive failed."
		return CRITICAL
	cmd = 'echo "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X" | sudo spamc -t 20 -n 20 -r -c -U /var/run/spamassassin/spamd.sock'
	process = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = process.communicate()
	if process.returncode != 1 or stdout.strip() == '' or stdout.strip() == '0/0':
		print "spamassassin virus test failed."
		return CRITICAL
	print service_status
	return OK
if __name__ == '__main__':
	sys.exit(main(sys.argv))
