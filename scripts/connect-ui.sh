#!/usr/bin/env bash
# Run on your own computer, not on the edge node.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/cluster.env"
[[ ! -f "$ROOT/cluster.local.env" ]] || source "$ROOT/cluster.local.env"
key=${1:-}
# With no argument, use the same SSH config/agent as ssh team@PUBLIC_HOST.
options=(-N -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
[[ -z "$key" ]] || options+=(-i "$key" -o IdentitiesOnly=yes)
for port in 18088 19870 19868 19889 19864 19865 19866 18042 18043 18044; do
 options+=(-L "127.0.0.1:$port:127.0.0.1:$port")
done
echo 'Open http://127.0.0.1:18088 (YARN), :19870 (HDFS), :19889 (JobHistory). Ctrl+C closes the tunnel.'
exec ssh "${options[@]}" "$SSH_USER@$PUBLIC_HOST"
