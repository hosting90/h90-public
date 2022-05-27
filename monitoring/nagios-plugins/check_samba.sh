#!/bin/bash

rt=0

(pgrep smbd >/dev/null) || {
  echo "no smbd process!"
  rt=2
}

(pgrep nmbd >/dev/null) || {
  echo "no nmbd process!"
  rt=2
}

if [ $rt -eq 0 ]; then
  echo "smbd/nmbd found"
fi;

exit $rt

