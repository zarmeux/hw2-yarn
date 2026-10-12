#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
echo 'Prerequisite: HW1 HDFS must already be healthy.'
hdfs dfsadmin -safemode get | grep -q 'Safe mode is OFF'
for ip in "${ALL_IPS[@]}"; do
  run_node "$ip" test -x /opt/hadoop/bin/yarn
  if [[ "$ip" != "$CONTROL_IP" ]]; then
    run_node "$ip" mkdir -p "$REMOTE_PROJECT/scripts"
    scp -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$ROOT/cache/known_hosts" "$ROOT/scripts/node-setup.sh" "$SSH_USER@$ip:$REMOTE_PROJECT/scripts/"
  fi
  memory=$WORKER_MEMORY_MB; cores=2
  if [[ "$ip" == "$NAMENODE_IP" ]]; then memory=$NN_WORKER_MEMORY_MB; cores=1; fi
  run_node "$ip" sudo -n bash "$REMOTE_PROJECT/scripts/node-setup.sh" "$ip" "$CONTROL_IP" "$NAMENODE_IP" "$memory" "$cores"
done
hdfs dfs -mkdir -p /yarn-logs /mr-history/tmp /mr-history/done /user/yarn
hdfs dfs -chmod 1777 /yarn-logs /mr-history/tmp
hdfs dfs -chown yarn:yarn /mr-history/done /user/yarn
hdfs dfs -chmod 770 /mr-history/done /user/yarn
bash "$ROOT/scripts/cluster.sh" restart
sudo -n bash "$ROOT/scripts/publish.sh" "$PUBLIC_HOST" "$UI_USER" "$CONTROL_IP" "$NAMENODE_IP" "$SECONDARY_IP" "${WORKER_IPS[@]}"
bash "$ROOT/scripts/verify.sh"
echo 'DEPLOY_OK'
