#!/usr/bin/python3

import nftables
import json
import sys

nft = nftables.Nftables()
nft.set_json_output(True)
rc, output, error = nft.cmd("list ruleset")

output = json.loads(output)["nftables"]

def match(data, filter):
  for key in filter.keys():
    if key not in data.keys():
      return False
    if data[key] != filter[key]:
      return False
  return True

def find(data, key, **kwargs):
  filtered = list()
  for i in data:
    if key not in i.keys():
      continue
    i = i[key]
    if not match(i, kwargs):
      continue
    filtered.append(i)
  return filtered


results = {}

results["default_input_policy_drop"] = False
if find(output, "chain", family="inet", type="filter", hook="input", policy="drop"):
  results["default_input_policy_drop"] = True


rt = 0

for check in results.keys():
  if results[check] == False:
    print(check, "- failed")
    rt = 2

if rt == 0:
  print("All checks passed")

sys.exit(rt)


