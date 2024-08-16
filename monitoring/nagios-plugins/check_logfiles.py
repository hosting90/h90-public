#!/usr/bin/python3

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

import sys
import argparse
import dateutil
import dateutil.parser
import re
import os
import datetime
import time
import smtplib

def send_email_log(subject,msg):
	receivers = ['admin@hosting90.cz']
	failed_receivers = []
	for receiver in receivers:
		try:
			sender = 'naemon@naemon.hosting90.cz'
			smtpObj = smtplib.SMTP('localhost')
			smtpObj.sendmail(sender, receiver, """%s""" % ('From: <'+sender+'>\nTo: <'+receiver+'>\nSubject: '+subject+'\n\n'+msg))
		except:
			try:
				passwd = 'H904dminM4il'
				sender = 'admin@hosting90.cz'
				smtpObj = smtplib.SMTP("smtp.hosting90.cz")
				smtpObj.login(sender, passwd)
				smtpObj.sendmail(sender, receiver, """%s""" % ('From: <'+sender+'>\nTo: <'+receiver+'>\nSubject: '+subject+'\n\n'+msg))
			except:
				failed_receivers.append(receiver)
	if len(failed_receivers) > 0:
		print("Cannot sent email to receiver(s): "+", ".join(failed_receivers))
		return UNKNOWN
	return OK	

def readlines_reverse(filename):
	with open(filename) as qfile:
		qfile.seek(0, os.SEEK_END)
		position = qfile.tell()
		line = ''
		while position >= 0:
			qfile.seek(position)
			next_char = qfile.read(1)
			if next_char == "\n":
				yield line[::-1]
				line = ''
			else:
				line += next_char
			position -= 1
		yield line[::-1]
		
def main(args):
	parser = argparse.ArgumentParser(description='Check log file')
	parser.add_argument('--logfile', action="append", dest="logfile", required=True)
	parser.add_argument('--datetimepattern', action="append", dest="datetimepattern", required=True)
	parser.add_argument('--email_subject', action="store", dest="email_subject", required=True)
	parser.add_argument('--minute', action="store", dest="minute", required=True)
	parser.add_argument('--crit', action="append", dest="crit", required=False, default=[])
	parser.add_argument('--warn', action="append", dest="warn", required=False, default=[])
	parser.add_argument('--ignore', action="append", dest="ignore", required=False, default=[])
	parser.add_argument('--nowarning', action="store", dest="nowarning", required=False, default=False)
	parser.add_argument('--limit', action="store", dest="limit", required=False, default=1)
	args = parser.parse_args()

	log_path = args.logfile
	datetimepattern = [re.compile(pat) for pat in args.datetimepattern]
	log_emailsubject = args.email_subject
	log_minute = int(args.minute)
	criticalpattern = [re.compile(pat) for pat in args.crit]
	warningpattern = [re.compile(pat) for pat in args.warn]
	ignorepattern = [re.compile(pat) for pat in args.ignore]
	log_nowarningemail = bool(args.nowarning)
	log_critical_limit = int(args.limit)

	start_datetime = datetime.datetime.now()
	critical_records = []
	warning_records = []

	for f in log_path:
		if (start_datetime - datetime.datetime.strptime(time.ctime(os.path.getmtime(f)), "%a %b %d %H:%M:%S %Y")) > datetime.timedelta(minutes=log_minute):
			continue
		for line in readlines_reverse(f):
			line = line.strip()
			if line == '':
				continue
			for m in datetimepattern:
				try:
					stop = (start_datetime - dateutil.parser.parse(re.search(m,line).group(1))) > datetime.timedelta(minutes=log_minute)
					break
				except:
					stop = False
			if stop: break
			if any(m.search(line) for m in ignorepattern): continue
			if any(m.search(line) for m in criticalpattern): critical_records.append([line, f])
			if any(m.search(line) for m in warningpattern): warning_records.append([line, f])

	for i in reversed(list(range(0,len(critical_records)))):
		if critical_records[i] in warning_records: critical_records.pop(i)
		
	status = OK
	if len(warning_records) > 0 or len(critical_records) > 0:
		status = WARNING
	if len(critical_records) >= log_critical_limit:
		status = CRITICAL
	if status == OK:
		print('No tracked record detected within last '+str(log_minute)+' minutes.')
		return OK

	msg = 'Host: %s\n' % os.uname()[1].strip()

	for f in log_path:
		f_critical = []
		f_warning = []

		for i in critical_records:
			if i[1] == f:
				f_critical.append(i[0])
		for i in warning_records:
			if i[1] == f:
				f_warning.append(i[0])

		if (len(f_warning) > 0) or (len(f_critical) > 0):
			msg += '\nFile %s:\n' % f
		if (status == CRITICAL) and (len(f_critical) > 0):
			msg += 'Status: CRITICAL;\n\nList of %s criticals:\n%s\n' % (len(f_critical),'\n'.join(f_critical))
			if len(f_warning) > 0:
				msg += '\nList of %s warnings:\n%s\n' % (len(f_warning),'\n'.join(f_warning))
		elif (status == WARNING) and (len(f_warning) > 0):
			msg += 'Status: WARNING;\n'
			if len(f_critical) > 0: msg += '\nList of %s criticals:\n%s\n' % (len(f_critical),'\n'.join(f_critical))
			if len(f_warning) > 0: msg += '\nList of %s warnings:\n%s' % (len(f_warning),'\n'.join(f_warning))
		
	print('Tracked record was found (w = %s, c = %s).' % (len(warning_records),len(critical_records)))
	if not (status == WARNING and log_nowarningemail is True):
		send_email_log('%s %s' % (log_emailsubject,os.uname()[1].strip().split('.')[0].strip()),msg)
	return status
	
if __name__ == '__main__':
	sys.exit(main(sys.argv))
