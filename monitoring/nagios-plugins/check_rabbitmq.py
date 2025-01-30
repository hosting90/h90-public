#!/usr/bin/python3

import requests
import argparse
from requests.auth import HTTPBasicAuth
import sys

# Function to check RabbitMQ local node status
def check_rabbitmq_local_node(username, password, host, port):
    base_url = f'http://{host}:{port}/api/'
    
    try:
        # Fetch overview data
        overview_url = f"{base_url}overview"
        overview_response = requests.get(overview_url, auth=HTTPBasicAuth(username, password))
        overview_response.raise_for_status()
        overview_data = overview_response.json()
        rmq_version = overview_data.get('rabbitmq_version')
        local_node = overview_data.get('node')

        if not local_node:
            print("CRITICAL - Unable to determine local RabbitMQ node name")
            sys.exit(2)

        # Fetch data for the local node
        node_url = f"{base_url}nodes/{local_node}"
        node_response = requests.get(node_url, auth=HTTPBasicAuth(username, password))
        node_response.raise_for_status()
        node_data = node_response.json()

        # Calculate memory and file descriptor usage
        memory_used_mb = node_data['mem_used'] / 1024 / 1024
        memory_limit_mb = node_data.get('mem_limit', 0) / 1024 / 1024
        memory_percentage = (memory_used_mb / memory_limit_mb) * 100 if memory_limit_mb else 0

        fd_used = node_data['fd_used']
        fd_total = node_data['fd_total']
        fd_percentage = (fd_used / fd_total) * 100 if fd_total else 0

        # Check if RabbitMQ is running
        if node_data.get('running'):
            print(f"OK - RabbitMQ {rmq_version} is running on {node_data['name']} | Memory Used: {memory_used_mb:.2f} MB ({memory_percentage:.2f}%), File Descriptors Used: {fd_used}/{fd_total} ({fd_percentage:.2f}%)")
            sys.exit(0)
        else:
            print(f"CRITICAL - RabbitMQ is NOT running on {node_data['name']} | Memory Used: {memory_used_mb:.2f} MB ({memory_percentage:.2f}%), File Descriptors Used: {fd_used}/{fd_total} ({fd_percentage:.2f}%)")
            sys.exit(2)

    except requests.exceptions.RequestException as e:
        print(f"CRITICAL - Error accessing RabbitMQ API: {e}")
        sys.exit(2)

# Main function
def main():
    parser = argparse.ArgumentParser(description='Icinga2 check for RabbitMQ local node status.')
    parser.add_argument('--username', required=True, help='RabbitMQ username')
    parser.add_argument('--password', required=True, help='RabbitMQ password')
    parser.add_argument('--host', default='localhost', help='RabbitMQ host (default: localhost)')
    parser.add_argument('--port', type=int, default=15672, help='RabbitMQ API port (default: 15672)')
    args = parser.parse_args()
    check_rabbitmq_local_node(args.username, args.password, args.host, args.port)

if __name__ == '__main__':
    main()

