#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
ready=0
for ((i=0;i<36;i++)); do
 if curl -fsS --max-time 5 "http://$CONTROL_IP:8088/ws/v1/cluster/nodes" > "$ROOT/cache/nodes.json"; then
  if python3 - "$ROOT/cache/nodes.json" "${WORKER_IPS[@]}" <<'PY'
import json,sys,socket
nodes=(json.load(open(sys.argv[1])).get('nodes') or {}).get('node',[])
actual={socket.gethostbyname(n['nodeHostName']) for n in nodes if n['state']=='RUNNING'}
sys.exit(0 if actual==set(sys.argv[2:]) and len(nodes)==3 else 1)
PY
  then ready=1; break; fi
 fi
 sleep 5
done
[[ $ready == 1 ]] || { echo 'Three RUNNING NodeManagers not found.' >&2; exit 1; }
bash "$ROOT/scripts/cluster.sh" status
# Each invocation uses a new namespace and leaves its evidence in HDFS.
probe="/user/yarn/hw2-check-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
printf 'hadoop yarn hadoop\nyarn cluster\n' > "$ROOT/cache/input.txt"
hdfs dfs -mkdir -p "$probe/input"
hdfs dfs -put - "$probe/input/words.txt" < "$ROOT/cache/input.txt"
hdfs dfs -chown -R yarn:yarn "$probe"
sudo -n -u yarn timeout 240 env HADOOP_CONF_DIR=/etc/hadoop-yarn /opt/hadoop/bin/hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar wordcount "$probe/input" "$probe/output" 2>&1 | tee "$ROOT/logs/wordcount-latest.txt"
app=$(sed -n 's/.*Submitted application \(application_[0-9]*_[0-9]*\).*/\1/p' "$ROOT/logs/wordcount-latest.txt" | tail -1)
[[ -n "$app" ]] || { echo 'No YARN application ID; local mode is not acceptable.' >&2; exit 1; }
yarn application -status "$app" | tee "$ROOT/logs/application-latest.txt"
grep -q 'Final-State : SUCCEEDED' "$ROOT/logs/application-latest.txt"
hdfs dfs -cat "$probe/output/part-r-*" | sort > "$ROOT/logs/wordcount-result.txt"
printf 'cluster\t1\nhadoop\t2\nyarn\t2\n' | diff -u - "$ROOT/logs/wordcount-result.txt"
job=${app/application_/job_}
history=0
for ((i=0;i<24;i++)); do
 if curl -fsS --max-time 5 "http://$CONTROL_IP:19888/ws/v1/history/mapreduce/jobs/$job" > "$ROOT/cache/job-history.json"; then history=1; break; fi
 sleep 5
done
[[ $history == 1 ]]
python3 - "$ROOT/cache/job-history.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))['job']
assert j['state']=='SUCCEEDED' and j['mapsCompleted']>=1 and j['reducesCompleted']>=1
print('JOB_HISTORY_OK',j['id'],j['state'])
PY
yarn logs -applicationId "$app" > "$ROOT/logs/aggregated-latest.txt" 2>&1
grep -q 'LogType:' "$ROOT/logs/aggregated-latest.txt"
echo 'LOG_AGGREGATION_OK'
python3 "$ROOT/scripts/check-links.py"
for port in 8443 8444 8445 8446 8451 8452 8453 8461 8462 8463; do
 # Resolve to the local edge address to test nginx; external reachability is a separate check.
 url="https://$PUBLIC_HOST:$port/"
 code=$(sudo -n curl -sS --max-time 15 --cacert /etc/nginx/hw2/server.crt --resolve "$PUBLIC_HOST:$port:$CONTROL_IP" --netrc-file /etc/nginx/hw2/access.netrc -L -o /dev/null -w '%{http_code}' "$url")
 [[ "$code" == 200 ]] || { echo "Bad authenticated UI: $url $code" >&2; exit 1; }
 anon=$(sudo -n curl -sS --max-time 10 --cacert /etc/nginx/hw2/server.crt --resolve "$PUBLIC_HOST:$port:$CONTROL_IP" -o /dev/null -w '%{http_code}' "$url")
 [[ "$anon" == 401 ]]
 mutation=$(sudo -n curl -sS --max-time 10 --cacert /etc/nginx/hw2/server.crt --resolve "$PUBLIC_HOST:$port:$CONTROL_IP" --netrc-file /etc/nginx/hw2/access.netrc -X PUT -o /dev/null -w '%{http_code}' "${url}ws/v1/cluster/apps/$app/state")
 [[ "$mutation" == 403 ]]
 echo "UI_OK $url authenticated=200 anonymous=401 PUT=403"
done
for port in 18088 19870 19868 19889 19864 19865 19866 18042 18043 18044; do
 curl -fsSL --max-time 15 "http://127.0.0.1:$port/" > /dev/null
 mutation=$(curl -sS --max-time 10 -X PUT -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/ws/v1/cluster/apps/$app/state")
 [[ "$mutation" == 403 ]]
 echo "SSH_UI_OK http://127.0.0.1:$port/ GET=200 PUT=403"
done
hdfs dfsadmin -report | tee "$ROOT/logs/hdfs-report.txt"
grep -q 'Live datanodes (3)' "$ROOT/logs/hdfs-report.txt"
hdfs fsck / -files -blocks > "$ROOT/logs/hdfs-fsck.txt"
grep -q 'Status: HEALTHY' "$ROOT/logs/hdfs-fsck.txt"
printf 'VERIFY_OK\nApplication: %s\nHDFS evidence: %s\n' "$app" "$probe"
