#!/usr/bin/python

# Script for monitoring memory usage.
# 
# check_memory -t|--type=physical|swap -w|--wlimit= -c|--climit= [-u|unit=] [-p|precision=]
#
# If an syntax error occured, command synopsis is printed on stderr.
# 
# The check_memory script understands the following OPTIONS.
# 
# -t physical|swap, --type=physical|swap
#		switch to monitoring usage of physical or swap memory 
# 
# -w value, --wlimit=value
#		set warning value. The value must be between 0 and max. memory on the host and cannot be greater than the critical limit.
#		The value can be immediately followed by the unit, fraction and percent are allowed as well. See unit option for allowed units.
# 		If unit is not specified, fraction value is expected. 
# 
# -c value, --climit=value
#		set critical value. The value must be between 0 and max. memory on the host and cannot be lower than the warning limit.
#		The value can be immediately followed by the unit, fraction and percent are allowed as well. See unit option for allowed units.
#		If unit is not specified, fraction value is expected. 
# 
# -u value, --unit=value
#		set unit for output message. Valid units are 'B' for bytes, 'KiB' for kibibytes (1024 bytes), 'MiB' for mebibytes (2^20 or 1,048,576 bytes), 
#		'GiB' for gibibytes (2^30 or 1,073,741,824 bytes), 'TiB' for tebibytes (2^40 or 1,099,511,627,776 bytes), 'PiB' for pebibytes (2^50 or 1,125,899,906,842,624 bytes),
#		'KB' for kilobytes (10^3 or 1,000 bytes), 'MB' for megabytes (10^6 or 1,000,000 bytes), 'GB' for gigabytes (10^9 or 1,000,000,000 bytes), 
#		'TB' for terabytes (10^12 or 1,000,000,000,000 bytes), 'PB' for petabytes (10^15 or 1,000,000,000,000,000 bytes)
#		If unit is not specified, MiB will be used. 
# 
# -p value, --precision=value
#		set precision of real numbers for output message. By default floats are rounded to 0 decimal place.

import sys
PYTHON_MODULES = ['getopt','subprocess','string','re','os']
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

def usage():
	print 'USAGE: '+sys.argv[0]+' -t|--type=physical|swap -w|--wlimit= -c|--climit= [-u|unit=] [-p|precision=]'
	sys.exit(UNKNOWN)

class Fraction:
	def __init__(self, value, unit):
		if is_number(value):
			if isinstance(value, int):
				self.value = int(value)
			else:
				self.value = float(value)
		else:
			raise TypeError
		if unit in ['', '%']:
			self.unit = unit
		else:
			raise TypeError

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

def parseLimit(limit):
	if type(limit) != type(''):
		raise TypeError
	tail = limit.lstrip(string.digits+'.')
	head = limit[:len(limit)-len(tail)]
	if is_number(head):
		limit_value = float(head)
	else:
		raise TypeError
	tail = tail.strip()
	if tail == '':
		return Fraction(limit_value,'')
	elif tail == '%':
		return Fraction(limit_value,'%')
	elif tail in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'KB', 'MB', 'GB', 'TB', 'PB']:
		return Quantity(limit_value,tail)
	else:
		raise ValueError

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
		sys.exit(UNKNOWN)

	try:
		centos_version = get_centos_version()
	except Exception, e:
		print str(e)
		return UNKNOWN
		
	try:
		opts, args = getopt.getopt(sys.argv[1:], "t:w:c:u:p:", ["type=","wlimit=","climit=","unit=","precision="])	
	except:
		usage()

	memtype = None
	wlimit = None
	climit = None
	unit = None
	precision = None
	for opt, arg in opts:
		if opt in ('-t', '--type'):
			memtype = arg
		elif opt in ('-w', '--wlimit'):
			wlimit = arg
		elif opt in ('-c', '--climit'):
			climit = arg
		elif opt in ('-u', '--unit'):
			unit = arg
		elif opt in ('-p', '--precision'):
			precision = arg
		else:
			usage()
	if memtype == None or wlimit == None or climit == None:
		usage()
 	if memtype != 'physical' and memtype !='swap':
		usage()

	# parse input limits
	try:
		wlimit=parseLimit(wlimit)
	except (TypeError, ValueError):
		usage()
	try:
		climit=parseLimit(climit)
	except (TypeError, ValueError):
		usage()
	
	# parse unit for output values
	if unit == None:
		unit = 'MiB'
	elif unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'KB', 'MB', 'GB', 'TB', 'PB']:
		pass
	else:
		usage

	# parse precision for output values
	if precision == None:
		precision = 0
	else:
		if is_number(precision):
			if isWhole(float(precision)):
				precision = int(precision)
			else:
				usage()
		else:
			usage()
	
	# get memory usage	
	if centos_version[0] == 7:
		mem_check_process = subprocess.Popen(['free','-b'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	else:	
		mem_check_process = subprocess.Popen(['free','-b','-o'], stdin=None, stdout = subprocess.PIPE, stderr=None)
	stdout, stderr = mem_check_process.communicate()
	if mem_check_process.returncode != 0 or stdout.strip() == '':
		print "UNKNOWN: unable to get memory usage!"
		return UNKNOWN
	if memtype == 'physical':
		mem_value_list = stdout.split('\n')[1].split()
	elif memtype == 'swap':
		mem_value_list = stdout.split('\n')[2].split()
	else:
		print "UNKNOWN: something wrong, unable to get memory usage!"
		return UNKNOWN

	mem_total = Quantity(long(mem_value_list[1]), 'B')
	mem_used = Quantity(long(mem_value_list[2]), 'B')
	mem_free = Quantity(long(mem_value_list[3]), 'B')
	
	# if swap is off
	if memtype == 'swap' and mem_total == Quantity(0,'B'):
		if os.path.exists('/root/.noswap'):
			print "OK: Swap is off and should be off."
		else:
			print "WARNING: swap missing!"
		return WARNING

	mem_usage = mem_used / mem_total

	# caclulate comparing limits
	if isinstance(wlimit,Fraction):
		if wlimit.unit == '':
			wlimit_checking_value = wlimit.value*mem_total
		elif wlimit.unit == '%':
			wlimit_checking_value = 0.01*wlimit.value*mem_total
	else:
		wlimit_checking_value = Quantity(wlimit.value,wlimit.unit)

	if isinstance(climit,Fraction):
		if climit.unit == '':
			climit_checking_value = climit.value*mem_total
		elif climit.unit == '%':
			climit_checking_value = 0.01*climit.value*mem_total
	else:
		climit_checking_value = Quantity(climit.value,climit.unit)

	swap_emptying = False
	# check if swap is being emptied
	if memtype == 'swap':
		cmd = 'ps aux | grep swapoff | grep -v grep 2>/dev/null'
		swapoff_check_process = subprocess.Popen(cmd, stdin=None, stdout=subprocess.PIPE, stderr=None, shell=True)
		stdout, stderr = swapoff_check_process.communicate()
		if swapoff_check_process.returncode == 0 and stdout.strip() != '':
			swap_emptying = True

	# check values of comparing limits
	if wlimit_checking_value > climit_checking_value:
		print "UNKNOWN: warning limit cannot be greater than critical limit!"
		return UNKNOWN
	if memtype == 'swap' and swap_emptying == True:
		print 'OK: %s memory is being emptied %s / %s' % (memtype,mem_used.convertto(unit).getstring(precision),mem_total.convertto(unit).getstring(precision))
		return WARNING
	else:
		if wlimit_checking_value < Quantity(0,'B') or wlimit_checking_value > mem_total:
			print "UNKNOWN: warning limit is out of range, max. %s memory on the host: %s" % (memtype,mem_total.convertto(unit).getstring(precision))
			return UNKNOWN
		if climit_checking_value < Quantity(0,'B') or climit_checking_value > mem_total:
			print "UNKNOWN: critical limit is out of range, max. %s memory on the host: %s" % (memtype,mem_total.convertto(unit).getstring(precision))
			return UNKNOWN

	# comparing limits to memory usage
	if mem_used > climit_checking_value:
		status = CRITICAL
	elif mem_used > wlimit_checking_value:
		status = WARNING
	else:
		status = OK
	
	# output message
	if status == CRITICAL:
		print 'CRITICAL: %s memory usage %s / %s' % (memtype,mem_used.convertto(unit).getstring(precision),mem_total.convertto(unit).getstring(precision))
	elif status == WARNING:
		print 'WARNING: %s memory usage %s / %s' % (memtype,mem_used.convertto(unit).getstring(precision),mem_total.convertto(unit).getstring(precision))
	elif status == OK:
		print 'OK: %s memory usage %s / %s' % (memtype,mem_used.convertto(unit).getstring(precision),mem_total.convertto(unit).getstring(precision))
	else:
		status = UNKNOWN
		print 'UNKNOWN'
	return status

if __name__ == '__main__':
	sys.exit(main(sys.argv))
