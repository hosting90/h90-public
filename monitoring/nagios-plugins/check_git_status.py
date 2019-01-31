#!/usr/bin/python

import sys
PYTHON_MODULES = ['argparse', 'subprocess', 'os', 'time']
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

def main(args):
	try:
		os.mkdir('/var/tmp/git_status')
	except:
		pass
	status = 0
	out_of_date = []
	# check python version
	if sys.version_info < (2, 4):
		print "UNKNOWN: python 2.4 or greater is required!"
		return UNKNOWN

	arg_parser = argparse.ArgumentParser(description='Used as nrpe plugin to monitor git status.')
	arg_parser.add_argument('-d', '--directory', nargs=1, required=True)
	arg_parser.add_argument('-b', '--branch', nargs='+', required=True)
	arguments = arg_parser.parse_args()

	try:
		os.chdir(arguments.directory[0])
	except:
		print 'No such file or directory!'
		return UNKNOWN

	subprocess.call(['git', 'remote', 'update'])

	for branch in arguments.branch:
		branch_file = '/var/tmp/git_status/.' + branch
		process = subprocess.Popen(['git', 'diff', 'origin/' + branch, '--stat'], stdin=None, stdout = subprocess.PIPE, stderr=subprocess.PIPE, shell=False)
		stdout, stderr = process.communicate()

		if not stdout.strip():
			try:
				os.remove(branch_file)
			except:
				pass
		else:
			with open(branch_file, 'a'): pass

		if not os.path.exists(branch_file):
			status += OK
		if (time.time() - os.stat(branch_file).st_mtime) > 600:
			status += CRITICAL
			out_of_date.append(branch)
		else:
			status += OK

	if status == OK:
		print 'All branches are up to date.'
		return OK
	else:
		print 'Branch/es ' + str(out_of_date) + ' out of date!'
		return CRITICAL


if __name__ == '__main__':
	sys.exit(main(sys.argv))
