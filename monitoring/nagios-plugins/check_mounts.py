#!/usr/bin/python

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

import sys
PYTHON_MODULES = ['re','os','subprocess','smtplib','datetime','time']
for module in PYTHON_MODULES:
	try:
		locals()[module] = __import__(str(module))
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

def main(args):
	allow_mount = False
	check_write = True
	if(len(args) == 2 and args[1] == '--no-write-test'):
		check_write = False

	elif len(sys.argv[1:]) > 0:
		allow_mount = True
		try:
			SERVICESTATE = sys.argv[1]
			SERVICESTATETYPE = sys.argv[2]
			SERVICEATTEMPT = sys.argv[3]
		except IndexError:
			print "Wrong arguments."
			return UNKNOWN
		if not ((SERVICESTATE == 'CRITICAL' or SERVICESTATE == 'ERROR' or SERVICESTATE == 'WARNING') and (SERVICESTATETYPE == 'HARD' or SERVICESTATETYPE == 'SOFT')):
			print "OK: Do nothing"
			return OK
		if int(SERVICEATTEMPT) != 1:
			print "OK: Do nothing"
			return OK

	try:
		centos_version = get_centos_version()
	except Exception, e:
		print str(e)
		return UNKNOWN

	f = open('/etc/fstab','r')
	fstab = f.readlines()
	f.close()

	failed = []
	failed_umount = []
	success = []
	start_datetime = datetime.datetime.now()
	for mount in fstab:
		if re.search(r'^#',mount.strip()) != None:
			continue

		mount_split = mount.strip().split()
		if len(mount_split) == 0:
			continue

		mount_dest = mount_split[1].strip().rstrip('/')
		mount_type = mount_split[2].strip()
		mount_opt = mount_split[3].strip()
		if re.search(r'nfs',mount_type,re.IGNORECASE):
			if centos_version[0] < 7:
				process = subprocess.Popen(['sudo', 'timeout', '20s', 'mountpoint', mount_dest], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
			else:
				process = subprocess.Popen(['sudo', 'timeout', '-k', '6s', '20s', 'mountpoint', mount_dest], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)

		elif re.search(r'none',mount_type,re.IGNORECASE) and re.search(r'bind',mount_opt,re.IGNORECASE):
			if centos_version[0] < 7:
				process = subprocess.Popen('cat /proc/self/mounts | grep %s' % mount_dest, stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
			else:
				process = subprocess.Popen(['sudo', 'timeout', '-k', '6s', '20s', 'mountpoint', mount_dest], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)

		else:
			continue

		if not os.path.exists(mount_dest):
			if not allow_mount:
				print "Directory %s does not exist." % (mount_dest)
				return WARNING

		stdout, stderr = process.communicate()
		if process.returncode != 0:
			if allow_mount and re.search(r'nfs',mount_type,re.IGNORECASE) != None and re.search(r'home',mount_dest) == None:
				if re.search('Stale file handle',stderr) != None:
					process = subprocess.Popen(['sudo','umount','-l',mount_dest], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
					stdout, stderr = process.communicate()
					if process.returncode != 0:
						failed_umount.append("mountpoint: %s\nstdout: %s\nstderr: %s\n" % (mount_dest,stdout,stderr))

				process = subprocess.Popen(['sudo','mount',mount_dest], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
				stdout, stderr = process.communicate()
				if process.returncode != 0:
					failed.append("moutpoint: %s\nstdout: %s\nstderr: %s\n" % (mount_dest,stdout,stderr))

				else:
					success.append(mount_dest)

			else:
				print "%s is not mounted." % mount_dest
				return CRITICAL

		if re.search(r'none',mount_type,re.IGNORECASE) and re.search(r'bind',mount_opt,re.IGNORECASE):
			continue

		if not allow_mount:
			if(check_write):
				test_file = os.path.join(mount_dest, ".mount_test_"+os.urandom(8).encode('hex'))
				process = subprocess.Popen(['sudo','touch',test_file], stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
				stdout, stderr = process.communicate()
				if process.returncode != 0:
					print "Write test on %s failed." % mount_dest
					return CRITICAL

				test_dst_file = os.path.join(mount_dest, ".mount_test_"+os.urandom(8).encode('hex'))
				process = subprocess.Popen(['sudo','mv',test_file, test_dst_file], stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
	                        stdout, stderr = process.communicate()
				if process.returncode != 0:
					print "Move test on %s failed." % mount_dest
					return CRITICAL

				process = subprocess.Popen(['sudo','touch',test_file], stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
				stdout, stderr = process.communicate()
				if process.returncode != 0:
					print "Write test on %s failed." % mount_dest
					return CRITICAL

				process = subprocess.Popen(['sudo','mv',test_file, test_dst_file], stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
	                        stdout, stderr = process.communicate()
				if process.returncode != 0:
					print "Rewrite test on %s failed." % mount_dest
					return CRITICAL

				process = subprocess.Popen(['sudo','rm','-f',test_file, test_dst_file], stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
				stdout, stderr = process.communicate()
				if process.returncode != 0:
					print "Write test on %s failed." % mount_dest
					return CRITICAL

		# cistic selhanych reziduii
		if(check_write):
			all_test_files = [ os.path.join(mount_dest,fn) for fn in filter(lambda file_: re.search(r'.mount_test',file_), os.walk(mount_dest).next()[2]) ]
			failed_test_files = filter(lambda file_: os.path.exists(file_) and (start_datetime - datetime.datetime.fromtimestamp(os.path.getmtime(file_))) > datetime.timedelta(minutes=60) ,all_test_files)
			if len(failed_test_files) > 0:
				process = subprocess.Popen(['sudo','rm','-f']+failed_test_files, stdin=None, stdout = subprocess.PIPE, stderr=None, shell=False)
				stdout, stderr = process.communicate()

	if allow_mount:
		if len(failed) > 0:
			print "Unable to mount %s." % ("\n".join(failed))
			outmsg = "Unable to mount.\n\n%s." % ("\n".join(failed))
			if len(failed_umount) > 0:
				outmsg += "\n\nUnable to unmount %s." % (", ".join(failed_umount))
			if len(success) > 0:
				outmsg += "\n\nSuccessfully to mounted %s." % (", ".join(success))
			send_email_log(outmsg)
			return CRITICAL

		else:
			print "Mounting successful."
			if len(success) > 0:
				outmsg = "Successfully mounted %s." % (", ".join(success))
				send_email_log(outmsg)
			return OK
	else:
		print "All mounts are mounted."
		return OK

if __name__ == '__main__':
	sys.exit(main(sys.argv))
