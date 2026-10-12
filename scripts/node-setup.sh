#!/usr/bin/env bash
# Root, additive deployment. Does not edit or format HDFS storage/configuration.
set -euo pipefail
NODE_IP=$1 RM_IP=$2 NN_IP=$3 MEMORY=$4 VCORES=$5
[[ $EUID == 0 && -x /opt/hadoop/bin/yarn && -e /etc/hadoop/core-site.xml ]] || exit 1
if [[ -e /etc/hadoop-yarn && ! -e /etc/hadoop-yarn/.hw2-managed ]]; then
  echo 'Unmanaged /etc/hadoop-yarn found; refusing to overwrite.' >&2; exit 1
fi
id yarn >/dev/null 2>&1 || useradd --system --create-home --home-dir /home/yarn --shell /bin/bash yarn
install -d -m 0755 /etc/hadoop-yarn
cp -r --update=none /etc/hadoop/. /etc/hadoop-yarn/
touch /etc/hadoop-yarn/.hw2-managed
install -d -o yarn -g yarn -m 0750 /var/lib/hadoop-yarn /var/lib/hadoop-yarn/local /var/lib/hadoop-yarn/logs /var/lib/hadoop-yarn/tmp /var/lib/hadoop-yarn/run /var/log/hadoop-yarn
JAVA_HOME=$(find /usr/lib/jvm -maxdepth 1 -type d -name 'java-11-openjdk-*' | sort | head -n 1)
[[ -x "$JAVA_HOME/bin/java" ]]
cat > /etc/hadoop-yarn/hadoop-env.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=/opt/hadoop
export HADOOP_MAPRED_HOME=/opt/hadoop
export HADOOP_CONF_DIR=/etc/hadoop-yarn
export HADOOP_LOG_DIR=/var/log/hadoop-yarn
export HADOOP_PID_DIR=/var/lib/hadoop-yarn/run
export HADOOP_HEAPSIZE_MAX=512m
EOF
cat > /etc/hadoop-yarn/yarn-env.sh <<'EOF'
export YARN_RESOURCEMANAGER_HEAPSIZE=512
export YARN_NODEMANAGER_HEAPSIZE=384
export YARN_RESOURCEMANAGER_OPTS="-Xmx512m"
export YARN_NODEMANAGER_OPTS="-Xmx384m"
EOF
cat > /etc/hadoop-yarn/mapred-env.sh <<'EOF'
export HADOOP_MAPRED_HOME=/opt/hadoop
export HADOOP_LOG_DIR=/var/log/hadoop-yarn
export HADOOP_JOB_HISTORYSERVER_HEAPSIZE=384
export MAPRED_HISTORYSERVER_OPTS="-Xmx384m"
EOF
python3 - "$NN_IP" "$RM_IP" "$NODE_IP" "$MEMORY" "$VCORES" <<'PY'
import sys, pathlib, xml.etree.ElementTree as E
nn,rm,node,memory,cores=sys.argv[1:]
def write(name, props):
    root=E.Element('configuration')
    for key,value in props.items():
        p=E.SubElement(root,'property')
        E.SubElement(p,'name').text=key
        E.SubElement(p,'value').text=str(value)
    E.indent(root)
    E.ElementTree(root).write('/etc/hadoop-yarn/'+name,encoding='UTF-8',xml_declaration=True)
write('core-site.xml',{'fs.defaultFS':f'hdfs://{nn}:9000','hadoop.tmp.dir':'/var/lib/hadoop-yarn/tmp'})
write('yarn-site.xml',{
 'yarn.resourcemanager.hostname':rm,'yarn.resourcemanager.bind-host':rm,
 'yarn.resourcemanager.address':f'{rm}:8032','yarn.resourcemanager.scheduler.address':f'{rm}:8030',
 'yarn.resourcemanager.resource-tracker.address':f'{rm}:8031','yarn.resourcemanager.admin.address':f'{rm}:8033',
 'yarn.resourcemanager.webapp.address':f'{rm}:8088',
 'yarn.nodemanager.hostname':node,'yarn.nodemanager.bind-host':node,
 'yarn.nodemanager.address':f'{node}:45454','yarn.nodemanager.localizer.address':f'{node}:8040',
 'yarn.nodemanager.webapp.address':f'{node}:8042','yarn.nodemanager.resource.memory-mb':memory,
 'yarn.nodemanager.resource.cpu-vcores':cores,
 'yarn.scheduler.minimum-allocation-mb':256,'yarn.scheduler.maximum-allocation-mb':2048,
 'yarn.scheduler.minimum-allocation-vcores':1,'yarn.scheduler.maximum-allocation-vcores':2,
 'yarn.nodemanager.local-dirs':'/var/lib/hadoop-yarn/local','yarn.nodemanager.log-dirs':'/var/lib/hadoop-yarn/logs',
 'yarn.nodemanager.aux-services':'mapreduce_shuffle',
 'yarn.nodemanager.env-whitelist':'JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME',
 'yarn.nodemanager.pmem-check-enabled':'true','yarn.nodemanager.vmem-check-enabled':'false',
 'yarn.log-aggregation-enable':'true','yarn.nodemanager.remote-app-log-dir':'/yarn-logs',
 'yarn.log.server.url':f'http://{rm}:19888/jobhistory/logs',
 'yarn.acl.enable':'true','yarn.admin.acl':'yarn',
 'yarn.resourcemanager.recovery.enabled':'true',
 'yarn.resourcemanager.store.class':'org.apache.hadoop.yarn.server.resourcemanager.recovery.FileSystemRMStateStore',
 'yarn.resourcemanager.fs.state-store.uri':'file:///var/lib/hadoop-yarn/rm-state'})
write('mapred-site.xml',{
 'mapreduce.framework.name':'yarn','mapreduce.application.classpath':'/opt/hadoop/share/hadoop/mapreduce/*,/opt/hadoop/share/hadoop/mapreduce/lib/*',
 'mapreduce.jobhistory.address':f'{rm}:10020','mapreduce.jobhistory.webapp.address':f'{rm}:19888',
 'mapreduce.jobhistory.bind-host':rm,'mapreduce.jobhistory.intermediate-done-dir':'/mr-history/tmp',
 'mapreduce.jobhistory.done-dir':'/mr-history/done',
 'mapreduce.map.memory.mb':512,'mapreduce.map.java.opts':'-Xmx384m',
 'mapreduce.reduce.memory.mb':512,'mapreduce.reduce.java.opts':'-Xmx384m',
 'yarn.app.mapreduce.am.resource.mb':512,'yarn.app.mapreduce.am.command-opts':'-Xmx384m',
 'yarn.app.mapreduce.am.staging-dir':'/user/yarn/staging',
 'mapreduce.task.io.sort.mb':128})
write('capacity-scheduler.xml',{
 'yarn.scheduler.capacity.root.queues':'default','yarn.scheduler.capacity.root.default.capacity':100,
 'yarn.scheduler.capacity.root.default.maximum-capacity':100,
 'yarn.scheduler.capacity.root.default.state':'RUNNING',
 'yarn.scheduler.capacity.root.default.acl_submit_applications':'yarn',
 'yarn.scheduler.capacity.root.default.acl_administer_queue':'yarn',
 'yarn.scheduler.capacity.maximum-am-resource-percent':0.25,
 'yarn.scheduler.capacity.root.default.user-limit-factor':1})
PY
for role in resourcemanager nodemanager historyserver; do
  bin=yarn; [[ "$role" != historyserver ]] || bin=mapred
  cat > "/etc/systemd/system/hadoop-$role.service" <<EOF
[Unit]
Description=Hadoop YARN/MapReduce $role
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=yarn
Group=yarn
Environment=JAVA_HOME=$JAVA_HOME
Environment=HADOOP_HOME=/opt/hadoop
Environment=HADOOP_MAPRED_HOME=/opt/hadoop
Environment=HADOOP_CONF_DIR=/etc/hadoop-yarn
ExecStart=/opt/hadoop/bin/$bin $role
StandardOutput=append:/var/log/hadoop-yarn/$role.log
StandardError=inherit
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
UMask=0027
[Install]
WantedBy=multi-user.target
EOF
done
systemctl daemon-reload
echo "SETUP_OK $NODE_IP containers=${MEMORY}MB/${VCORES}vcores"
