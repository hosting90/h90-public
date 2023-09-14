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
msgs = {}

#
# check if default input policy is set to drop
#

t = "default_input_policy_drop"
results[t] = False
msgs[t] = "check if firewall is configured"
if find(output, "chain", family="inet", type="filter", hook="input", policy="drop"):
  results[t] = True

#
# check if "counter" is the last rule in input chain
#

t = "default_input_policy_counter"
results[t] = False
msgs[t] = "counter rule not found / not last, runtime rules added?"

rules = find(output, "rule", family="inet", table="filter", chain="input")
rules.sort(key=lambda x: x["handle"])
last_rule = rules[-1] if rules else []

if last_rule and set(last_rule["expr"][0].keys()) == { "counter" }:
  results[t] = True

#
# finish
#

rt = 0

for check in results.keys():
  if results[check] == False:
    print(check, "- failed,", msgs[check])
    rt = 2

if rt == 0:
  print("All checks passed")

sys.exit(rt)


