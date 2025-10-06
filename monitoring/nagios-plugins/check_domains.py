#!/usr/bin/env python3

import argparse
import yaml
import mysql.connector
import sys

PASS_FILE = "/root/secrets/pass.yaml"
QUERY_FILE = "/root/secrets/db_secrets.enc"

def load_credentials():
    try:
        with open(PASS_FILE, 'r') as f:
            data = yaml.safe_load(f)
        return data['user'], data['pass'], data['db'], data.get('host', 'localhost')
    except Exception as e:
        print(f"CRITICAL: Failed to read credentials: {e}")
        sys.exit(2)

def load_query(check_key):
    try:
        with open(QUERY_FILE, 'r') as f:
            queries = yaml.safe_load(f)
        if check_key not in queries:
            raise KeyError(f"Query for '{check_key}' not found")
        return queries[check_key]
    except Exception as e:
        print(f"CRITICAL: Failed to load query: {e}")
        sys.exit(2)

def execute_query(user, password, host, db, query):
    try:
        conn = mysql.connector.connect(
            user=user,
            password=password,
            host=host,
            database=db
        )
        cursor = conn.cursor()
        cursor.execute(query)
        result = cursor.fetchone()
        cursor.close()
        conn.close()
        if result is None or len(result) == 0:
            raise Exception("No result returned from query")
        return int(result[0])
    except Exception as e:
        print(f"CRITICAL: SQL query failed: {e}")
        sys.exit(2)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", choices=["wp", "en", "sk", "cz"], required=True, help="What to check: wp, en, sk, cz")
    parser.add_argument("--warning", type=int, required=True, help="Warning threshold")
    parser.add_argument("--critical", type=int, required=True, help="Critical threshold")
    args = parser.parse_args()

    user, password, db, host = load_credentials()
    query = load_query(args.check)
    count = execute_query(user, password, host, db, query)

    if count >= args.critical:
        print(f"CRITICAL: {count} domains for check '{args.check}'")
        sys.exit(2)
    elif count >= args.warning:
        print(f"WARNING: {count} domains for check '{args.check}'")
        sys.exit(1)
    else:
        print(f"OK: {count} domains for check '{args.check}'")
        sys.exit(0)

if __name__ == "__main__":
    main()
