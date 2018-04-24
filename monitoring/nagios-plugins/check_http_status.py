#!/usr/bin/python

# Script for monitoring httpd process status.
# 
# check_http_status -w|--wlimit= -c|--climit=
#

import sys
PYTHON_MODULES = ['getopt','subprocess','string','re','os','smtplib','traceback']
for module in PYTHON_MODULES:
	try:
		locals()[module] = __import__(str(module))
	except ImportError:
 		print "UNKNOWN: cannot load %s module!" % module
		sys.exit(UNKNOWN)

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def get_centos_version():
	try:
		fd = open('/etc/redhat-release','r')
	except:
		raise Exception("UNKNOWN: cannot get CentOS version!")
	rr = re.search('[a-zA-Z ]+([\.\d]+)',fd.read().strip())
	fd.close()
	if rr != None:
		centos_version = map(int,rr.group(1).split('.'))
	else:
		raise Exception("UNKNOWN: cannot parse CentOS version!")
	return centos_version

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

# puvodni verze pouzita k detekci problemu, ted nevyuzivana
def puvodni_main(args):
	try:
		opts, args = getopt.getopt(sys.argv[1:], "w:c:", ["wlimit=","climit="])	
	except:
		usage()

	wlimit = None
	climit = None
	for opt, arg in opts:
		if opt in ('-w', '--wlimit'):
			wlimit = arg
		elif opt in ('-c', '--climit'):
			climit = arg
		else:
			usage()
	if wlimit == None or climit == None:
		usage()

	# parse input limits
	try:
		wlimit=int(wlimit)
		climit=int(climit)
	except ValueError:
		usage()
	
	try:
		centos_version = get_centos_version()
	except Exception, e:
		send_email_log("UNKNOWN: unable to get centos version!\n\n%s\n\n" % e)
		print str(e)
		return UNKNOWN
		
	# get apachectl fullstatus
	if centos_version[0] == 7:
		process = subprocess.Popen(['links','-dump','http://127.0.0.2/server-status'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE)
	else:
		process = subprocess.Popen(['apachectl','fullstatus'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE)
	stdout, stderr = process.communicate()
	if process.returncode != 0 or re.search('Connection refused',stderr):
		send_email_log("UNKNOWN: unable to get statuslist!\n\n%s\n\n%s" % (stdout, stderr))
		print "UNKNOWN: unable to get statuslist!"
		return UNKNOWN

	mymatch1 = re.compile(r'\n([ ]*Srv[ ]+PID[ ]+Acc[ ]+M[ ]+CPU[ ]+SS[ ]+Req[ ]+Conn[ ]+Child[ ]+Slot[ ]+Client[ ]+VHost[ ]+Request[ ]*)\n')
	try:
		m_position = int(re.search(mymatch1,stdout.strip()).group(1).index(" M "))+1
	except Exception, e:
		send_email_log("UNKNOWN: unable to find mode position!\n\n%s\n\n%s\n\n%s" % (e,stdout, stderr))
		print "UNKNOWN: unable to find mode position!"
		return UNKNOWN
	
	mymatch2 = re.compile(r'\n[ ]*Srv[ ]+PID[ ]+Acc[ ]+M[ ]+CPU[ ]+SS[ ]+Req[ ]+Conn[ ]+Child[ ]+Slot[ ]+Client[ ]+VHost[ ]+Request[ ]*\n(.*)\n[ ]+[-]+\n',re.DOTALL)
	rr = re.search(mymatch2,stdout.strip())
	if rr == None:
		send_email_log("UNKNOWN: regex failed!\n\n"+stdout.strip())
		print "UNKNOWN: regex failed!"
		return UNKNOWN
	
	counter = 0
	mymatch3 = re.compile(r'(\n[ ]+)')
	statuslist = re.sub(mymatch3," ",rr.group(1)).strip()
	for line in statuslist.split('\n'):
		if line[m_position] == 'G':
			counter += 1

	if counter >= climit:
		send_email_log("CRITICAL: There are %i apache procs in G operation mode\n\n%s" % (counter,stdout.strip()))
		print "There are %i apache procs in G operation mode" % counter
		return CRITICAL
	if counter >= wlimit:
		send_email_log("WARNING: There are %i apache procs in G operation mode\n\n%s" % (counter,stdout.strip()))
		print "There are %i apache procs in G operation mode" % counter
		return WARNING

	print "There are %i apache procs in G operation mode" % counter
	return OK

def get_active_proc_pid():
	active_proc_pid = None
	for pidfile in ['/var/run/httpd/httpd.pid','/var/run/httpd.pid']:
		if os.path.exists(pidfile):
			active_proc_pid = int(open(pidfile,'r').read().strip())
			break;
	return active_proc_pid

def get_zombie_proc_pids(active_proc_pid):
	# root procesy zabit zrejme nechceme
	cmd = "pgrep -P 1 -f httpd -u root | grep -v %s" % active_proc_pid
	process = subprocess.Popen(cmd, stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = process.communicate()
	if process.returncode != 0:
		root_procs = []
	else:
		root_procs = stdout.strip().split('\n')
	# zombici vcetne root procesu
	cmd = "pgrep -P 1 -f httpd | grep -v %s" % active_proc_pid
	process = subprocess.Popen(cmd, stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = process.communicate()
	if process.returncode != 0:
		return []
	zombie_procs = stdout.strip().split('\n')
	# odstranime root procesy
	for proc in root_procs:
		if proc in zombie_procs:
			zombie_procs.remove(proc)
	return zombie_procs

def kill_zombie_proc(zombie_pid):
	sudo = "kill"
	process = subprocess.Popen(['kill','-9',zombie_pid], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	if process.returncode != 0:
		sudo = "sudo kill"
		process = subprocess.Popen(['sudo','kill','-9',zombie_pid], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
		stdout, stderr = process.communicate()		
	return process.returncode, stdout, stderr, sudo

def get_pid_owner(pid):
	process = subprocess.Popen(['ps','h','-p',pid,'-o','ruser'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
	stdout, stderr = process.communicate()
	pid_owner = stdout.strip()
	
	cmd = "ls -l /home | grep %s" % pid_owner
	process = subprocess.Popen(cmd, stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = process.communicate()
	if process.returncode != 0:
		return pid_owner
	else:
		return stdout.strip()[53:]

def usage():
	print 'USAGE: '+sys.argv[0]+' -w|--wlimit= -c|--climit='
	sys.exit(UNKNOWN)

def main(args):
	try:
		opts, args = getopt.getopt(sys.argv[1:], "w:c:", ["wlimit=","climit="])	
	except:
		usage()

	wlimit = None
	climit = None
	for opt, arg in opts:
		if opt in ('-w', '--wlimit'):
			wlimit = arg
		elif opt in ('-c', '--climit'):
			climit = arg
		else:
			usage()
	killer_mode = False
	if wlimit == None or climit == None:
		if 'OK' or 'WARNING' or 'ERROR' or 'UNKNOWN' in args and 'SOFT' or 'HARD' in args:
			killer_mode = True
		else:
			usage()

	# vetev pro zabijeni zombiku
	if killer_mode:
		try:
			SERVICESTATE = sys.argv[1]
			SERVICESTATETYPE = sys.argv[2]
			SERVICEATTEMPT = sys.argv[3]
		except IndexError:
			usage()

		if not ((SERVICESTATE == 'CRITICAL' or SERVICESTATE == 'ERROR' or SERVICESTATE == 'WARNING') and (SERVICESTATETYPE == 'HARD' or SERVICESTATETYPE == 'SOFT')):
			print "OK: Do nothing"
			return OK

		proc = subprocess.Popen(["pgrep","-P","1","-f","check_http_status.py"], stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
		stdout, stderr = proc.communicate()
		if proc.returncode == 0:
			print "OK: Another process is running. Do nothing"
			return OK

		# FORK aby nam to nrpe nezabijelo
		try:
			pid = os.fork()
			if pid > 0:
				print "OK: Fork passed."
				return OK
		except OSError, e:
			send_email_log("UNKNOWN: Fork failed.\n\n"+str(e)+"\n\n"+traceback.format_exc())
			print "UNKNOWN: Fork failed."
			return UNKNOWN
		# Decouple from parent environment
		os.chdir("/")
		os.setsid()
		os.umask(0)
		try:
			pid = os.fork()
			if pid > 0:
				print "OK: Fork-2 passed."
				return OK
		except OSError, e:
			send_email_log("UNKNOWN: Fork-2 failed.\n\n"+str(e)+"\n\n"+traceback.format_exc())
			print "UNKNOWN: Fork-2 failed."
			return UNKNOWN

		if len(stdout.strip().split('\n')) > 1:
			print "SYN flood traffic is already recording. Do nothing"
			return WARNING
		

		active_proc_pid = get_active_proc_pid()
		if active_proc_pid == None:
			send_email_log("UNKNOWN: pid file not found!")
			print "UNKNOWN: pid file not found!"
			return UNKNOWN
		
		dead_procs = get_zombie_proc_pids(active_proc_pid)
		number_dead_procs = len(dead_procs)
		if number_dead_procs == 0:
			print "OK: No http zombie proc. Do nothing"
			return OK
		
		msg = ""
		for zombie_pid in dead_procs:
			domain = get_pid_owner(zombie_pid)
			returncode, stdout, stderr, sudo = kill_zombie_proc(zombie_pid)
			msg += "%s %s: %s [%s]\n" % (sudo,zombie_pid,returncode,domain)
			if stdout.strip() != "":
				msg += stdout.strip()+"\n"
			if stderr.strip() != "":
				msg += stderr.strip()+"\n"
			msg += "\n"
			
		send_email_log("EVENTHANDLER: killing zombie http procs... \n\n%s" % (msg))	
		
		print "Killing httpd procs"
		return OK
	
	# vetev pro kontrolovani zombiku
	try:
		wlimit=int(wlimit)
		climit=int(climit)
	except ValueError:
		usage()
	
	active_proc_pid = get_active_proc_pid()
	if active_proc_pid == None:
		send_email_log("UNKNOWN: pid file not found!")
		print "UNKNOWN: pid file not found!"
		return UNKNOWN
	
	dead_procs = get_zombie_proc_pids(active_proc_pid)
	number_dead_procs = len(dead_procs)

	if number_dead_procs >= climit:
		print "There are %i zombie http procs (%s)" % (number_dead_procs," ".join(dead_procs))
		return CRITICAL
	if number_dead_procs >= wlimit:
		print "There are %i zombie http procs (%s)" % (number_dead_procs," ".join(dead_procs))
		return WARNING
	if number_dead_procs == 0:
		print "No http zombie proc"
		return OK
	print "There are %i zombie http procs (%s)" % (number_dead_procs," ".join(dead_procs))
	
	return OK
	
if __name__ == '__main__':
	sys.exit(main(sys.argv))
