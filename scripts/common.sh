#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/cluster.env"
[[ ! -f "$ROOT/cluster.local.env" ]] || source "$ROOT/cluster.local.env"
for ip in "$CONTROL_IP" "$NAMENODE_IP" "$SECONDARY_IP" "${WORKER_IPS[@]}"; do
  python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$ip"
done
[[ "$PUBLIC_HOST" =~ ^[a-zA-Z0-9.-]+$ && "$UI_USER" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 1
[[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ && "$REMOTE_PROJECT" =~ ^/[a-zA-Z0-9_./-]+$ ]] || exit 1
[[ ${#WORKER_IPS[@]} == 3 && $(printf '%s\n' "${WORKER_IPS[@]}" | sort -u | wc -l) == 3 ]] || exit 1
for memory in "$NN_WORKER_MEMORY_MB" "$WORKER_MEMORY_MB"; do
  [[ "$memory" =~ ^[0-9]+$ ]] && ((memory >= 512)) || { echo 'Worker memory must be an integer >= 512 MiB.' >&2; exit 1; }
done
hostname -I | tr ' ' '\n' | grep -qxF "$CONTROL_IP" || { echo 'Run on the configured edge node.' >&2; exit 1; }
mapfile -t ALL_IPS < <(printf '%s\n' "$CONTROL_IP" "${WORKER_IPS[@]}" | sort -u)
mkdir -p "$ROOT/cache" "$ROOT/logs"
SSH_OPTIONS=(-n -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$ROOT/cache/known_hosts")
run_node() {
  local ip=$1 command_line; shift
  if [[ "$ip" == "$CONTROL_IP" ]]; then "$@"; else
    printf -v command_line '%q ' "$@"
    ssh "${SSH_OPTIONS[@]}" "$SSH_USER@$ip" "$command_line"
  fi
}
hdfs() { sudo -n -u hadoop env HADOOP_CONF_DIR=/etc/hadoop /opt/hadoop/bin/hdfs "$@"; }
yarn() { sudo -n -u yarn env HADOOP_CONF_DIR=/etc/hadoop-yarn /opt/hadoop/bin/yarn "$@"; }
