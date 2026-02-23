#!/bin/bash
set -e

# Fix permissions on /data if it exists (Railway mounts volumes as root)
if [ -d "/data" ]; then
  chown -R node:node /data 2>/dev/null || true
fi

# Drop to node user and exec the command
exec gosu node "$@"
