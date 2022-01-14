import re
import sys

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

status_file = '/usr/local/nagios/var/status.dat'

def main():
	ret_code = OK
	ret_msg_dict = {0: [], 1: [], 2: [], 3: []}
	ret_msg = ''

	with open(status_file) as file:
		for line in file:
			if 'servicestatus {' in line:
				for i in range(15):
					myline = file.next().strip()
					if re.match('host_name', myline):
						host_name = myline.strip().split('=', 1)[1]
					if re.match('service_description', myline):
						service_description = myline.strip().split('=', 1)[1]
					if re.match('current_state', myline):
						current_state = myline.strip()
					else:
						current_state = ''
					if 'current_state=3' in current_state:
						if ret_code < UNKNOWN:
							ret_code = UNKNOWN
						ret_msg_dict[3].append('{} - {}'.format(host_name, service_description))
					if 'current_state=2' in current_state:
						if ret_code < CRITICAL:
							ret_code = CRITICAL
						ret_msg_dict[2].append('{} - {}'.format(host_name, service_description))
					if 'current_state=1' in current_state:
						if ret_code < WARNING:
							ret_code = WARNING
						ret_msg_dict[1].append('{} - {}'.format(host_name, service_description))

	if ret_code > CRITICAL:
		ret_msg += 'UNKNOWN:\n' + '\n'.join(ret_msg_dict[3])
	if ret_code > WARNING:
		ret_msg += 'CRITICAL:\n' + '\n'.join(ret_msg_dict[2])
	if ret_code > OK:
		ret_msg += 'WARNING:\n' + '\n'.join(ret_msg_dict[1])
	if ret_code >= OK:
		ret_msg += 'OK:\n' + '\n'.join(ret_msg_dict[0])
	print(ret_msg)
	return ret_code

if __name__ == '__main__':
	sys.exit(main())
