#!/usr/bin/python3

import requests, sys, argparse

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def main(args):
	ret_code = OK
	ret_msg_list = []
	for version in args.php_versions:
		try:
			resp = requests.get(f'http://{version}.{args.inetname}', timeout=30)
			if resp.status_code != 200:
				ret_code = CRITICAL
				ret_msg_list.append(f'{version}.{args.inetname} returned {resp.status_code}: {resp.content}')
		except Exception as e:
			ret_code = CRITICAL
			ret_msg_list.append(f'{version}.{args.inetname} reached exception: {e}')

	if ret_code > OK:
		ret_msg += f'Failed checks:\n' + '\n'.join(ret_msg_dict[2])
	else:
		ret_msg = 'All HTTP checks are ok'
	print(ret_msg)
	return ret_code


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description='Run nagios checks.')
	parser.add_argument('-i', action='store', dest='inetname', required=True)
	parser.add_argument('-p', action='append', dest='php_versions', required=True)
	args = parser.parse_args()
	sys.exit(main(args))
