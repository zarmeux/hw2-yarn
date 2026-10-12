#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
action=${1:-status}
case "$action" in
 start|restart)
  sudo -n systemctl enable hadoop-resourcemanager hadoop-historyserver >/dev/null
  sudo -n systemctl "$action" hadoop-resourcemanager hadoop-historyserver
  ready=0
  for ((i=0;i<30;i++)); do
   if curl -fsS --max-time 3 "http://$CONTROL_IP:8088/ws/v1/cluster/info" >/dev/null; then ready=1; break; fi
   sleep 2
  done
  [[ $ready == 1 ]] || { echo 'ResourceManager did not start.' >&2; exit 1; }
  for ip in "${WORKER_IPS[@]}"; do
   run_node "$ip" sudo -n systemctl enable hadoop-nodemanager >/dev/null
   run_node "$ip" sudo -n systemctl "$action" hadoop-nodemanager
  done;;
 stop)
  for ip in "${WORKER_IPS[@]}"; do run_node "$ip" sudo -n systemctl stop hadoop-nodemanager; done
  sudo -n systemctl stop hadoop-historyserver hadoop-resourcemanager;;
 status)
  sudo -n systemctl --no-pager --plain is-active hadoop-resourcemanager hadoop-historyserver
  for ip in "${WORKER_IPS[@]}"; do printf '%s ' "$ip"; run_node "$ip" systemctl is-active hadoop-nodemanager; done
  yarn node -list -all;;
 *) echo 'Usage: cluster.sh start|restart|stop|status' >&2; exit 2;;
esac
