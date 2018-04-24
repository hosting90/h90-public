#!/usr/bin/python

# Script provides event handler tool for check_swap service in nagios/nrpe.
# 
# restart_swap SERVICESTATE SERVICESTATETYPE SERVICEATTEMPT
# 
# If missed swap is detected and there is no file /root/.noswap, event handler turns swap on.
#
# Arguments are provided by nagios/nrpe. If SERVICESTATE is WARNING or CRITICAL and SERVICESTATETYPE is SOFT or HARD, then script detects amount of free physical memory.
# If there is enough free physical memory (size is greater than usage swap memory), it tries to empty swap. Script turns off swap, if swap is empty, reactivates swap.
# 
# PLEASE consider settings for free parameters 'buffers_as_free', 'cached_as_free', 'safe_limit'
# 

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

import sys
PYTHON_MODULES = ['getopt','subprocess','string','re','smtplib','os','datetime','traceback']
for module in PYTHON_MODULES:
	try:
		locals()[module] = __import__(str(module))
	except ImportError:
 		print "UNKNOWN: cannot load %s module!" % module
		sys.exit(UNKNOWN)

### !!! SET if buffers and cache (physical) memory should be counted as a free memory !!!
buffers_as_free = True
cached_as_free = True

### !!! SET safe limit for free memory size, which should be kept untouched in any case !!!
safe_limit = 0.2 # it means that at least 10% of total physical memory must remain free, after all

# for email message
unit='MiB'
precision=0

def usage():
	print 'USAGE: '+sys.argv[0]+' SERVICESTATE SERVICESTATETYPE SERVICEATTEMPT'
	sys.exit(UNKNOWN)

class Quantity:
	def __init__(self, value, unit):
		if is_number(value):
			if isinstance(value, int):
				self.value = int(value)
			else:
				self.value = float(value)
		else:
			raise ValueError
		if unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'KB', 'MB', 'GB', 'TB', 'PB']:
			self.unit = unit
		else:
			raise ValueError
			
	def convertto(self,unit):
		if type(unit) != type(''):
			raise TypeError
		if not unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'KB', 'MB', 'GB', 'TB', 'PB']:
			raise ValueError
		try:
			factor = getUnitFactor(self.unit) / float(getUnitFactor(unit))
		except:
			raise
		return Quantity(self.value * factor,unit)

	def normalised(self,base=2):
		if type(base) != type(0):
			raise TypeError
		if base == 2:
			for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']:
				cQ = self.convertto(unit)
				if abs(cQ).value > 1 and abs(cQ).value < 1000:
					return cQ
		elif base == 10:
			for unit in ['B', 'KB', 'MB', 'GB', 'TB', 'PB']:
				cQ = self.convertto(unit)
				if abs(cQ).value > 1 and abs(cQ).value < 1000:
					return cQ
		else:
			raise ValueError 
		return self

	def getnormalisedstring(self,base=2,precision=0):
		if type(base) != type(0):
			raise TypeError
		if type(precision) != type(0):
			raise TypeError
		nQ = self.normalised(base)
		return "%.*f %s" % (precision,nQ.value,nQ.unit)

	def getstring(self,precision=0):
		if type(precision) != type(0):
			raise TypeError
		return "%.*f %s" % (precision,self.value,self.unit)
	
	def __eq__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value == other.convertto('B').value:
				return True
			else:
				return False		
		elif isinstance(self,Quantity) and type(other) == type(None):
			return False
		elif isinstance(other,Quantity) and type(self) == type(None):
			return False		
		else:
			raise TypeError
			
	def __ne__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value != other.convertto('B').value:
				return True
		elif isinstance(self,Quantity) and type(other) == type(None):
			return True
		elif isinstance(other,Quantity) and type(self) == type(None):
			return True
		else:
			raise TypeError

	def __lt__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value < other.convertto('B').value:
				return True
			else:
				return False		
		else:
			raise TypeError

	def __gt__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value > other.convertto('B').value:
				return True
			else:
				return False		
		else:
			raise TypeError

	def __le__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value <= other.convertto('B').value:
				return True
			else:
				return False		
		else:
			raise TypeError

	def __ge__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if self.convertto('B').value >= other.convertto('B').value:
				return True
			else:
				return False		
		else:
			raise TypeError

	def __add__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			return Quantity(self.convertto('B').value + other.convertto('B').value,'B')
		else:
			raise TypeError
			
	def __sub__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			return Quantity(self.convertto('B').value - other.convertto('B').value,'B')
		else:
			raise TypeError

	def __mul__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			Quantity(self.convertto('B').value * other.convertto('B').value,'B')
		elif isinstance(self,Quantity) and is_number(other):
			return Quantity(self.value * other, self.unit)
		else:
			raise TypeError

	def __rmul__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			Quantity(self.convertto('B').value * other.convertto('B').value,'B')
		elif isinstance(self,Quantity) and is_number(other):
			return Quantity(self.value * other, self.unit)
		else:
			raise TypeError

	def __div__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if other.value == 0:
				raise ZeroDivisionError
			Quantity(self.convertto('B').value / float(other.convertto('B').value),'B')
		elif isinstance(self,Quantity) and is_number(other):
			if other == 0:
				raise ZeroDivisionError
			else:
				res = self.value / float(other)
				if isinstance(res, int):
					return Quantity(int(res), self.unit)
				else:
					return Quantity(res, self.unit)
		else:
			raise TypeError

	def __rdiv__(self, other):
		if isinstance(self,Quantity) and isinstance(other,Quantity):
			if other.value == 0:
				raise ZeroDivisionError
			Quantity(self.convertto('B').value / float(other.convertto('B').value),'B')
		elif isinstance(self,Quantity) and is_number(other):
			if other == 0:
				raise ZeroDivisionError
			else:
				res = self.value / float(other)
				if isinstance(res, int):
					return Quantity(int(res), self.unit)
				else:
					return Quantity(res, self.unit)
		else:
			raise TypeError

	def __neg__(self):
		return Quantity(-1*self.value,self.unit)

	def __abs__(self):
		if self >= Quantity(0,'B'):
			return self
		else:
			return -self

	def __str__(self):
		return "%s %s" % (self.value,self.unit)

def getUnitFactor(unit):
	if type(unit) != type(''):
		raise TypeError
	if unit == 'B':
		unit_factor = 1
	elif unit == 'KiB':
		unit_factor = 1024
	elif unit == 'MiB':
		unit_factor = 1024*1024
	elif unit == 'GiB':
		unit_factor = 1024*1024*1024
	elif unit == 'TiB':
		unit_factor = 1024*1024*1024*1024
	elif unit == 'PiB':
		unit_factor = 1024*1024*1024*1024*1024
	elif unit == 'KB':
		unit_factor = 1000
	elif unit == 'MB':
		unit_factor = 1000*1000
	elif unit == 'GB':
		unit_factor = 1000*1000*1000
	elif unit == 'TB':
		unit_factor = 1000*1000*1000*1000
	elif unit == 'PB':
		unit_factor = 1000*1000*1000*1000*1000
	else:
		raise ValueError
	return unit_factor

def is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False

def isWhole(x):
	if(x%1 == 0):
		return True
	else:
		return False

def send_email_log(msg):
	subject = hostname + ' - EVENTHANDLER restart_swap'
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
	# check python version
	if sys.version_info < (2, 4):
		print "UNKNOWN: python 2.4 or greater is required!"
		return UNKNOWN

	try:
		centos_version = get_centos_version()
	except Exception, e:
		print str(e)
		return UNKNOWN

	try:
		SERVICESTATE = sys.argv[1]
		SERVICESTATETYPE = sys.argv[2]
		SERVICEATTEMPT = sys.argv[3]
	except IndexError:
		usage()

	os.putenv('PATH','/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin')
	# get swap path
	swap_path = None
	mymatch1 = re.compile(r"swap")
	f = open('/etc/fstab','r')
	for line in f:
		if re.search(mymatch1,line) != None:
			swap_path = line.strip().split()[0].strip()
	f.close()
	if swap_path == None:
		send_email_log("UNKNOWN: unable to get swap path!")
		print "UNKNOWN: unable to get swap path!"
		return UNKNOWN

	# get memory usage
	if centos_version[0] == 7:
		proc = subprocess.Popen(['free','-b'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	else:
		proc = subprocess.Popen(['free','-b','-o'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	stdout, stderr = proc.communicate()
	if proc.returncode != 0 or stdout.strip() == '':
		send_email_log("UNKNOWN: unable to get memory usage!")
		print "UNKNOWN: unable to get memory usage!"
		return UNKNOWN

	physical_mem_list = stdout.split('\n')[1].split()
	physical_mem_total = Quantity(long(physical_mem_list[1]), 'B')
	physical_mem_used = Quantity(long(physical_mem_list[2]), 'B')
	physical_mem_free = Quantity(long(physical_mem_list[3]), 'B')
	physical_mem_shared = Quantity(long(physical_mem_list[4]), 'B')
	physical_mem_buffers = Quantity(long(physical_mem_list[5]), 'B')
	physical_mem_cached = Quantity(long(physical_mem_list[6]), 'B')

	swap_mem_list = stdout.split('\n')[2].split()
	swap_mem_total = Quantity(long(swap_mem_list[1]), 'B')
	swap_mem_used = Quantity(long(swap_mem_list[2]), 'B')
	swap_mem_free = Quantity(long(swap_mem_list[3]), 'B')

	# calculate free physical memory
	free_physical_mem = physical_mem_free
	if buffers_as_free == True:
		free_physical_mem += physical_mem_buffers
	if cached_as_free == True:
		free_physical_mem += physical_mem_cached
		
	safe_limit_mem = safe_limit*physical_mem_total
	free_mem_after = free_physical_mem - swap_mem_used - safe_limit_mem
		
	# for email message
	msg = 'Host status before calling of eventhandler script:\n\n'
	msg += '%s, %s, %s\n\n' % (SERVICESTATE,SERVICESTATETYPE,SERVICEATTEMPT)
	msg += 'swap memory usage = %s / %s\n' % (swap_mem_used.convertto(unit).getstring(precision),swap_mem_total.convertto(unit).getstring(precision))
	msg += 'physical memory usage = %s / %s\n' % (physical_mem_used.convertto(unit).getstring(precision),physical_mem_total.convertto(unit).getstring(precision))
	msg += 'physical memory: Shared, Buffers, Cached = %s, %s, %s\n' % (physical_mem_shared.convertto(unit).getstring(precision),physical_mem_buffers.convertto(unit).getstring(precision),physical_mem_cached.convertto(unit).getstring(precision))
	msg += 'buffers_as_free = %s, cached_as_free = %s, available free physical memory = %s\n' % (str(buffers_as_free),str(cached_as_free),free_physical_mem.convertto(unit).getstring(precision))
	msg += 'safe_limit = %s, minimum required free physical memory after swap being emptied = %s\n' % (safe_limit,safe_limit_mem.convertto(unit).getstring(precision))
	msg += 'calculating free physical memory after swap being emptied = %s' % (free_mem_after.convertto(unit).getstring(precision))

	if not ((SERVICESTATE == 'CRITICAL' or SERVICESTATE == 'ERROR' or SERVICESTATE == 'WARNING') and (SERVICESTATETYPE == 'HARD' or SERVICESTATETYPE == 'SOFT')):
#		send_email_log("OK: Swap is under limits. Do nothing\n\n"+msg)
		print "OK: Swap is under limits. Do nothing"
		return OK

	# check if swap is being emptied
	cmd = 'ps aux | grep "swapoff\|swapon\|sync" | grep -v rsync | grep -v async | grep -v sync_super | grep -v grep 2>/dev/null'
	proc = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = proc.communicate()
	if proc.returncode == 0 and stdout.strip() != '':
#		send_email_log("WARNING: swap is being emptied. Do nothing\n\n"+msg)
		print "WARNING: swap is being emptied. Do nothing"
		return WARNING

	if swap_mem_total == Quantity(0, 'B'):
		if os.path.exists('/root/.noswap'):
			send_email_log("OK: Swap is off and should be off. Do nothing.\n\n"+msg)
			print "OK: Swap is off and should be off. Do nothing."
			return OK
		cmd = 'sudo swapon '+swap_path
		proc = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
		stdout, stderr = proc.communicate()
		if proc.returncode != 0:
			send_email_log("Swap is off! Trying to turn it on...\n\nSwapon does not work!\n\n"+msg)
			print "UNKNOWN: swapon does not work!"
			return UNKNOWN
		send_email_log("Swap is off! Trying to turn it on...\n\nSwap has been turn on.\n\n"+msg)
		print "OK: swap has been turn on!"
		return OK

	# keep safe limit for free memory
	if (free_physical_mem - swap_mem_used) < safe_limit_mem:
		send_email_log("WARNING: there is not enough free physical memory - do nothing\n\n"+msg)
		print "WARNING: there is not enough free physical memory - do nothing"
		return WARNING

	# FORK aby nam to nrpe nezabijelo
	try:
		pid = os.fork()
		if pid > 0:
#			send_email_log("OK: Fork passed.\n\n"+msg)
			print "OK: Fork passed."
			return OK
	except OSError, e:
		send_email_log("UNKNOWN: Fork failed.\n\n"+msg+"\n\n"+str(e)+"\n\n"+traceback.format_exc())
		print "UNKNOWN: Fork failed."
		return UNKNOWN
	# Decouple from parent environment
	os.chdir("/")
	os.setsid()
	os.umask(0)
	try:
		pid = os.fork()
		if pid > 0:
#			send_email_log("OK: Fork-2 passed.\n\n"+msg)
			print "OK: Fork-2 passed."
			return OK
	except OSError, e:
		send_email_log("UNKNOWN: Fork-2 failed.\n\n"+msg+"\n\n"+str(e)+"\n\n"+traceback.format_exc())
		print "UNKNOWN: Fork-2 failed."
		return UNKNOWN

	start_time = datetime.datetime.now()
	# sync
	cmd = 'sudo sync'
	proc = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = proc.communicate()
	if proc.returncode != 0:
		send_email_log("UNKNOWN: sync does not work!\n\n"+msg)
		print "UNKNOWN: sync does not work!"
		return UNKNOWN
	# swap off/on
	cmd = 'sudo swapoff '+ swap_path + ' && sudo swapon '+swap_path
	proc = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
	stdout, stderr = proc.communicate()
	if proc.returncode != 0:
		send_email_log("UNKNOWN: swap off/on does not work!\n\n"+msg)
		print "UNKNOWN: swapoff/on does not work!"
		return UNKNOWN

	if centos_version[0] == 7:
		proc = subprocess.Popen(['free','-b'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	else:
		proc = subprocess.Popen(['free','-b','-o'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	stdout, stderr = proc.communicate()

	swap_mem_list = stdout.split('\n')[2].split()
	swap_mem_total = Quantity(long(swap_mem_list[1]), 'B')
	swap_mem_used = Quantity(long(swap_mem_list[2]), 'B')
	swap_mem_free = Quantity(long(swap_mem_list[3]), 'B')

	if swap_mem_total == Quantity(0, 'B') and not os.path.exists('/root/.noswap'):
		cmd = 'sudo swapon '+swap_path
		proc = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
		stdout, stderr = proc.communicate()
		if proc.returncode != 0:
			send_email_log("After empying swap is off! Trying to turn it on...\n\nSwapon does not work!\n\n"+msg)
			print "UNKNOWN: swapon does not work!"
			return UNKNOWN
		msg = "After empying swap is off! Trying to turn it on...\n\nSwap has been turn on.\n\n"+msg

	stop_time = datetime.datetime.now()
	delta_time = stop_time - start_time
	msg += '\nDuration of script execution = %s.%s s' % (delta_time.seconds,delta_time.microseconds)
#	send_email_log("OK: Swap was emptied.\n\n"+msg)
	print "OK: Swap was emptied."
	return OK

if __name__ == '__main__':
	sys.exit(main(sys.argv))
