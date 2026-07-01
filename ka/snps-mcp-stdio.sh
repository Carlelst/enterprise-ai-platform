#!/bin/bash
# Local stdio wrapper: SSH tunnel to remote SNPS MCP server
# Uses SSH multiplexing (ControlMaster) to eliminate connection delay

SSH_CONTROL="/tmp/snps-mcp-ssh-%r@%h:%p"

# Ensure master connection is alive in background
ssh -T -o BatchMode=yes \
  -o ControlMaster=auto \
  -o ControlPath="${SSH_CONTROL}" \
  -o ControlPersist=300 \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  -J ai.hse@10.9.200.12 \
  sp.shentao.lu@10.9.200.16 \
  /bin/true 2>/dev/null

# Use the persistent connection to launch MCP server
exec ssh -T -o BatchMode=yes \
  -o ControlMaster=auto \
  -o ControlPath="${SSH_CONTROL}" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  -J ai.hse@10.9.200.12 \
  sp.shentao.lu@10.9.200.16 \
  /AI/users/sp.shentao.lu/snps-mcp-launcher.sh
