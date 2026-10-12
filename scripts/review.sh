#!/usr/bin/env bash
# Check existing YARN applications and interfaces; no job submission or restart.
set -euo pipefail
export LC_ALL=C
source "$(dirname -- "$0")/common.sh"
printf 'YARN review: %s\n' "$(date -u +%FT%TZ)"
check_service() {
  local ip=$1 unit=$2
  [[ $(run_node "$ip" systemctl is-active "$unit") == active ]]
  [[ $(run_node "$ip" systemctl is-enabled "$unit") == enabled ]]
  printf 'SERVICE_OK %s %s active/enabled\n' "$ip" "$unit"
}
check_service "$CONTROL_IP" hadoop-resourcemanager
check_service "$CONTROL_IP" hadoop-historyserver
check_service "$CONTROL_IP" nginx
for ip in "${WORKER_IPS[@]}"; do check_service "$ip" hadoop-nodemanager; done
curl -fsS --max-time 10 "http://$CONTROL_IP:8088/ws/v1/cluster/nodes" > "$ROOT/cache/review-nodes.json"
curl -fsS --max-time 10 "http://$CONTROL_IP:8088/ws/v1/cluster/metrics" > "$ROOT/cache/review-metrics.json"
python3 - "$ROOT/cache/review-nodes.json" "$ROOT/cache/review-metrics.json" "${WORKER_IPS[@]}" <<'PY'
import json,socket,sys
nodes=(json.load(open(sys.argv[1])).get('nodes') or {}).get('node',[])
actual={socket.gethostbyname(n['nodeHostName']) for n in nodes if n['state']=='RUNNING'}
if actual!=set(sys.argv[3:]) or len(nodes)!=3:
    raise SystemExit(f'CHECK_FAILED NodeManagers: {actual}')
m=json.load(open(sys.argv[2]))['clusterMetrics']
if m['activeNodes']!=3 or m['lostNodes']!=0 or m['unhealthyNodes']!=0:
    raise SystemExit('CHECK_FAILED unhealthy or missing YARN nodes')
print(f'NODES_OK running=3 lost=0 unhealthy=0 memory={m["totalMB"]}MiB vcores={m["totalVirtualCores"]}')
PY
curl -fsS --max-time 10 "http://$CONTROL_IP:8088/ws/v1/cluster/apps" > "$ROOT/cache/review-apps.json"
app=$(python3 - "$ROOT/cache/review-apps.json" <<'PY'
import json,sys
apps=(json.load(open(sys.argv[1])).get('apps') or {}).get('app',[])
good=[a for a in apps if a['name']=='word count' and a['applicationType']=='MAPREDUCE'
      and a['state']=='FINISHED' and a['finalStatus']=='SUCCEEDED'
      and a.get('logAggregationStatus')=='SUCCEEDED']
if not good:
    raise SystemExit('CHECK_FAILED no completed WordCount with aggregated logs')
print(max(good,key=lambda a:a['finishedTime'])['id'])
PY
)
job=${app/application_/job_}
curl -fsS --max-time 10 "http://$CONTROL_IP:19888/ws/v1/history/mapreduce/jobs/$job" > "$ROOT/cache/review-history.json"
python3 - "$ROOT/cache/review-history.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))['job']
if j['state']!='SUCCEEDED' or j['mapsCompleted']<1 or j['reducesCompleted']<1:
    raise SystemExit('CHECK_FAILED incomplete MapReduce history')
print(f'JOB_OK {j["id"]} SUCCEEDED maps={j["mapsCompleted"]} reduces={j["reducesCompleted"]}')
PY
echo "LOG_AGGREGATION_OK $app"
for port in 18088 19870 19868 19889 19864 19865 19866 18042 18043 18044; do
  code=$(curl -sS --max-time 15 -L -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/")
  [[ "$code" == 200 ]] || { echo "CHECK_FAILED local UI port=$port status=$code" >&2; exit 1; }
  echo "SSH_UI_OK port=$port GET=200"
done
python3 "$ROOT/scripts/check-links.py"
for port in 8443 8444 8445 8446 8451 8452 8453 8461 8462 8463; do
  url="https://$PUBLIC_HOST:$port/"
  options=(--max-time 15 --cacert /etc/nginx/hw2/server.crt --resolve "$PUBLIC_HOST:$port:$CONTROL_IP")
  code=$(sudo -n curl -sS "${options[@]}" --netrc-file /etc/nginx/hw2/access.netrc -L -o /dev/null -w '%{http_code}' "$url")
  anon=$(sudo -n curl -sS "${options[@]}" -o /dev/null -w '%{http_code}' "$url")
  [[ "$code" == 200 && "$anon" == 401 ]] || { echo "CHECK_FAILED HTTPS port=$port authorized=$code anonymous=$anon" >&2; exit 1; }
  echo "HTTPS_LOCAL_OK port=$port authorized=200 anonymous=401"
done
echo 'PUBLIC_REACHABILITY_NOT_CHECKED: run check-public.py on an external computer.'
hdfs dfsadmin -safemode get | tee "$ROOT/logs/review-safemode.txt"
grep -q 'Safe mode is OFF' "$ROOT/logs/review-safemode.txt"
hdfs fsck / -files -blocks > "$ROOT/logs/review-fsck.txt"
grep -q 'Status: HEALTHY' "$ROOT/logs/review-fsck.txt"
echo 'HDFS_OK HEALTHY'
echo 'REVIEW_OK'
