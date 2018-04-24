#!/usr/bin/python
# Naemon event handler for httpd status

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# Email sending
# 0 - nothing
# 1 - critical
# 2 - unknown
# 3 - warning
# 4 - all
VERBOSITY = 2

import sys
PYTHON_MODULES = ['re','os','subprocess','smtplib','datetime', 'time','traceback','ConfigParser','platform']
for module in PYTHON_MODULES:
	try:
		locals()[module] = __import__(module, fromlist=[''])
	except ImportError:
 		print "UNKNOWN: cannot load %s module!" % module
		sys.exit(UNKNOWN)

def send_email_log(msg):
	subject = hostname + ' - check_http_status'
	try:
		sender = 'naemon@nagios.hosting90.cz'
		receiver = 'admin@hosting90.cz'
		smtpObj = smtplib.SMTP('localhost')
		smtpObj.sendmail(sender, receiver, """%s""" % ('From: <'+sender+'>\nTo: <'+receiver+'>\nSubject: '+subject+'\n\n'+msg))
	except:
		config = ConfigParser.ConfigParser()
		config.read('/etc/h90.conf')
		if config.has_section('general'):
			if config.has_option('general', 'mailer'):
				address = config.get('general', 'mailer')
				hostname = os.uname()[1].strip().split('.')[0].strip()
				curl = pycurl.Curl()
				curl.setopt(curl.URL, "%s?subject=%s&msg=%s" % (address, subject, msg))
				curl.perform()
				curl.close()

def main(args):
	try:
		SERVICESTATE = sys.argv[2]
		SERVICESTATETYPE = sys.argv[3]
		SERVICEATTEMPT = sys.argv[4]
	except IndexError:
		print "Wrong arguments."
		return UNKNOWN
	event_source = 'httpd'
	if len(sys.argv) > 5:
		event_source = sys.argv[5]
	if not ((SERVICESTATE == 'CRITICAL' or SERVICESTATE == 'ERROR' or SERVICESTATE == 'WARNING') and (SERVICESTATETYPE == 'HARD' or SERVICESTATETYPE == 'SOFT')):
		print "OK: Do nothing"
		return OK
	if SERVICESTATE == 'WARNING':
		print "WARNING: Do nothing"
		return OK
	
	procname = 'httpd'
	try:
		if platform.linux_distribution()[1].split('.')[0] == '6':
			procname = 'httpd.itk'
	except:
		pass
	
	hostname = os.uname()[1]
	config = ConfigParser.ConfigParser()
	config.read('/etc/hosting90.conf')
	if (event_source == 'php_error_log' and re.search(r'^onedesign-w[0-9]+',hostname) != None) or (config.has_section('general') and config.has_option('general', 'purpose') and config.get('general', 'purpose') != 'webserver'):
		if VERBOSITY >= 2:
			send_email_log("UNKNOWN: not allowed on this server")
		print "UNKNOWN: not allowed on this server."
		return OK

	cmd = 'ps aux | grep restart_httpd | grep -v nrpe | grep -v grep | wc -l'
	process = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = process.communicate()
	# We can still see ourselves
	if int(stdout) > 1:
		if VERBOSITY >= 3:
			send_email_log("WARNING: another process already running. Do nothing.")
		print "WARNING: another process already running."
		return WARNING

	outmsg = ''
	
	pidfile = None
	for f in ['/var/run/httpd/httpd.pid','/var/run/httpd.pid']:
		if os.path.exists(f):
			pidfile = f
			break
	if pidfile != None:
		# timestamp posouva take reload, nicmene nejaku pojistka proti prilis castemu restartu dame
		start_datetime = datetime.datetime.now()
		if hasattr(datetime, 'strptime'): strptime = datetime.datetime.strptime
		else: strptime = lambda date_string, format: datetime.datetime(*(time.strptime(date_string, format)[0:6]))
		ts = start_datetime - strptime(time.ctime(os.path.getmtime(pidfile)), "%a %b %d %H:%M:%S %Y")
		if ts < datetime.timedelta(hours=1):
			if VERBOSITY >= 4:
				send_email_log("OK: Pid file timestamp is too young. Do nothing.\n%s" % outmsg)
			print "OK: Pid file timestamp is too young. Do nothing."
			return OK
	
	# kontrola syntaxe
	process = subprocess.Popen(['sudo','/usr/sbin/apachectl','-t'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	if process.returncode != 0:
		if VERBOSITY >= 1:
			send_email_log("Critical: bad syntax in httpd config.")
		print "CRITICAL: bad syntax in httpd config."
		return CRITICAL
	
	# FORK aby nam to nrpe nezabijelo
	try:
		pid = os.fork()
		if pid > 0:
			print "OK: Fork passed."
			return OK
	except OSError, e:
		if VERBOSITY >= 2:
			send_email_log("UNKNOWN: Fork failed.\n\n"+outmsg+"\n\n"+str(e)+"\n\n"+traceback.format_exc())
		print "UNKNOWN: Fork failed."
		return UNKNOWN
	os.chdir("/")
	os.setsid()
	os.umask(0)
	try:
		pid = os.fork()
		if pid > 0:
			print "OK: Fork-2 passed."
			return OK
	except OSError, e:
		if VERBOSITY >= 2:
			send_email_log("UNKNOWN: Fork-2 failed.\n\n"+outmsg+"\n\n"+str(e)+"\n\n"+traceback.format_exc())
		print "UNKNOWN: Fork-2 failed."
		return UNKNOWN
	if pidfile != None:
		process = subprocess.Popen(['sudo','chmod','g+w',pidfile], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
		stdout, stderr = process.communicate()
		outmsg += 'sudo chmod g+w %s\n' % pidfile
		outmsg += 'returncode: '+str(process.returncode)+'\n'
		outmsg += 'stdout: '+stdout.strip()+'\n'
		outmsg += 'stderr: '+stderr.strip()+'\n'
		# Don't listen to output and just move forward
		process = subprocess.Popen(['sudo','service','httpd','stop'], stdin=None, stdout=None, stderr=None, close_fds=True, shell=False)
		time.sleep(2)
		# stdout, stderr = process.communicate()
		# outmsg += 'sudo service httpd stop\n'
		# outmsg += 'returncode: '+str(process.returncode)+'\n'
		# outmsg += 'stdout: '+stdout.strip()+'\n'
		# outmsg += 'stderr: '+stderr.strip()+'\n'
	process = subprocess.Popen(['sudo','killall','-9',procname], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	outmsg += 'sudo killall -9 httpd\n'
	outmsg += 'returncode: '+str(process.returncode)+'\n'
	outmsg += 'stdout: '+stdout.strip()+'\n'
	outmsg += 'stderr: '+stderr.strip()+'\n'
	# pockame 30 vterin na ukonceni vsech procesu
	check_timeout = time.time()+30
	try:
		while time.time() < check_timeout:
			subprocess.check_call(['pgrep','^'+procname+'$'],stdout = open('/dev/null','w'), stderr=open('/dev/null','w'))
			time.sleep(0.5)
	except:
		# pgrep skonci s errorem 1, kdyz uz procesy nejsou a skoci to sem
		pass
	process = subprocess.Popen(['sudo','service','httpd','start'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	outmsg += 'sudo service httpd start\n'
	outmsg += 'returncode: '+str(process.returncode)+'\n'
	outmsg += 'stdout: '+stdout.strip()+'\n'
	outmsg += 'stderr: '+stderr.strip()+'\n'
	if process.returncode == 0:
		print "OK: httpd restart succeeded."
		outmsg += 'OK: httpd restart succeeded.\n'
		if VERBOSITY >= 4:
			send_email_log(outmsg)
		return OK
	else:
		print "CRITICAL: httpd restart failed!"
		outmsg += 'CRITICAL: httpd restart failed!\n'
		if VERBOSITY >= 1:
			send_email_log(outmsg)
		return CRITICAL

if __name__ == '__main__':
	sys.exit(main(sys.argv))

