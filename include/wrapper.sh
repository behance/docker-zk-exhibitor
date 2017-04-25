#!/bin/bash -e
# -XX:+PrintGCTimeStamps and -XX:+PrintGCDateStamps
# HOSTNAME=`hostname --fqdn`
# IP=$(ping -c 1 "$HOSTNAME" | grep PING| cut -d' ' -f3| cut -d'(' -f2|cut -d')' -f1)

# wait 10 seconds instead of 30
# export JVM_OPTS="${JVM_OPTS} -Dcassandra.ring_delay_ms=10000"
# The flag Xmx specifies the maximum memory allocation pool for a Java Virtual Machine (JVM), 
# while Xms specifies the initial memory allocation pool.

# ENV ZINC_COMMAND=" \
#     java \
#     -server \
#     -XX:+UseG1GC \
#     -XX:+DoEscapeAnalysis \
#     -XX:+UseCompressedOops \
#     -XX:+UseCompressedClassPointers \
#     -XX:+HeapDumpOnOutOfMemoryError \
#     -XX:InitialHeapSize=$JAVA_HEAP \
#     -XX:MaxHeapSize=$JAVA_HEAP \
#     -XX:ThreadStackSize=$JAVA_STACK \
#     -XX:MetaspaceSize=$JAVA_META \
#     -XX:MaxMetaspaceSize=$JAVA_META \
#     -XX:InitialCodeCacheSize=$JAVA_CODE \
#     -XX:ReservedCodeCacheSize=$JAVA_CODE \
#     -Dzinc.home=$ZINC_FOLDER \
#     -classpath $ZINC_FOLDER/lib/*:. \
#     com.typesafe.zinc.Nailgun \
#     $ZINC_PORT $ZINC_TIMEOUT \
# "

# source: https://github.com/apache/storm/blob/master/conf/defaults.yaml
# ### worker.* configs are for task workers
# worker.heap.memory.mb: 768
# worker.childopts: "-Xmx%HEAP-MEM%m -XX:+PrintGCDetails -Xloggc:artifacts/gc.log -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1M -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=artifacts/heapdump"
# worker.gc.childopts: ""

export EXHIBITOR_JVM_OPTS="-Xmx512m"
export ZK_JVM_OPTS="-XX:+PrintCommandLineFlags -XX:+PrintGC -XX:+PrintGCCause -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCApplicationConcurrentTime -XX:+PrintGCApplicationStoppedTime -XX:+PrintTenuringDistribution -XX:+PrintAdaptiveSizePolicy -Xmx2g -Xms2g -XX:+AlwaysPreTouch -Xss512k"
# NOTE: This is set by default in zookeeper according to this 
# source: https://issues.apache.org/jira/browse/ZOOKEEPER-1670
# export SERVER_JVMFLAGS=""

# Generates the default exhibitor config and launches exhibitor

MISSING_VAR_MESSAGE="must be set"
DEFAULT_AWS_REGION="us-west-2"
DEFAULT_DATA_DIR="/opt/zookeeper/snapshots"
DEFAULT_LOG_DIR="/opt/zookeeper/transactions"
DEFAULT_ZK_ENSEMBLE_SIZE=0
S3_SECURITY=""
HTTP_PROXY=""
: ${HOSTNAME:?$MISSING_VAR_MESSAGE}
: ${AWS_REGION:=$DEFAULT_AWS_REGION}
: ${ZK_DATA_DIR:=$DEFAULT_DATA_DIR}
: ${ZK_LOG_DIR:=$DEFAULT_LOG_DIR}
: ${ZK_ENSEMBLE_SIZE:=$DEFAULT_ZK_ENSEMBLE_SIZE}
: ${HTTP_PROXY_HOST:=""}
: ${HTTP_PROXY_PORT:=""}
: ${HTTP_PROXY_USERNAME:=""}
: ${HTTP_PROXY_PASSWORD:=""}

cat <<- EOF > /opt/exhibitor/defaults.conf
	zookeeper-data-directory=$ZK_DATA_DIR
	zookeeper-install-directory=/opt/zookeeper
	zookeeper-log-directory=$ZK_LOG_DIR
	log-index-directory=$ZK_LOG_DIR
	cleanup-period-ms=300000
	check-ms=30000
	backup-period-ms=600000
	client-port=2181
	cleanup-max-files=20
	backup-max-store-ms=21600000
	connect-port=2888
	observer-threshold=0
	election-port=3888
	zoo-cfg-extra=tickTime\=2000&initLimit\=10&syncLimit\=5&quorumListenOnAllIPs\=true
	auto-manage-instances-settling-period-ms=0
	auto-manage-instances=1
	auto-manage-instances-fixed-ensemble-size=$ZK_ENSEMBLE_SIZE
EOF

# TODO: Add this back in? ^
# java-environment=export JAVA_OPTS\="$JAVA_OPTS"

# https://github.com/mesosphere/universe/blob/version-3.x/repo/packages/E/exhibitor/1/config.json
# "jvm_opts": {
# 	"default": "-Xmx512m",
# 	"description": "JVM opts for Exhibitor",
# 	"type": "string"

# "zookeeper": {
# 	"description": "ZooKeeper specific configuration properties",
# 	"properties": {
# 		"jvm_opts": {
# 			"default": "-XX:+PrintCommandLineFlags -XX:+PrintGC -XX:+PrintGCCause -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCApplicationConcurrentTime -XX:+PrintGCApplicationStoppedTime -XX:+PrintTenuringDistribution -XX:+PrintAdaptiveSizePolicy -Xmx2g -Xms2g -XX:+AlwaysPreTouch -Xss512k",
# 			"description": "JVM opts for Exhibitor",
# 			"type": "string"
# 		},

#   ],
#   "env": {
#     "EXHIBITOR_JVM_OPTS": "{{exhibitor.jvm_opts}}",
#     "ZK_JVM_OPTS": "{{exhibitor.zookeeper.jvm_opts}}"
#   },
#   "cmd": "/exhibitor-wrapper -c zookeeper --headingtext \"{{exhibitor.app-id}}\" --zkconfigconnect {{exhibitor.zk_servers}} --zkconfigzpath \"/exhibitor-dcos{{exhibitor.app-id}}\""
# }

# NEW, ENVIRONMENT VAR
cat <<EOF > /opt/zookeeper/conf/java.env
SERVER_JVMFLAGS="$SERVER_JVMFLAGS $ZK_JVM_OPTS"
EOF

if [[ -n ${AWS_ACCESS_KEY_ID} ]]; then
  cat <<- EOF > /opt/exhibitor/credentials.properties
    com.netflix.exhibitor.s3.access-key-id=${AWS_ACCESS_KEY_ID}
    com.netflix.exhibitor.s3.access-secret-key=${AWS_SECRET_ACCESS_KEY}
EOF
  S3_SECURITY="--s3credentials /opt/exhibitor/credentials.properties"
fi

if [[ -n ${S3_BUCKET} ]]; then
  echo "backup-extra=throttle\=&bucket-name\=${S3_BUCKET}&key-prefix\=${S3_PREFIX}&max-retries\=4&retry-sleep-ms\=30000" >> /opt/exhibitor/defaults.conf

  BACKUP_CONFIG="--configtype s3 --s3config ${S3_BUCKET}:${S3_PREFIX} ${S3_SECURITY} --s3region ${AWS_REGION} --s3backup true"
else
  BACKUP_CONFIG="--configtype file --fsconfigdir /opt/zookeeper/local_configs --filesystembackup true"
fi

if [[ -n ${ZK_PASSWORD} ]]; then
	SECURITY="--security web.xml --realm Zookeeper:realm --remoteauth basic:zk"
	echo "zk: ${ZK_PASSWORD},zk" > realm
fi


if [[ -n $HTTP_PROXY_HOST ]]; then
    cat <<- EOF > /opt/exhibitor/proxy.properties
      com.netflix.exhibitor.s3.proxy-host=${HTTP_PROXY_HOST}
      com.netflix.exhibitor.s3.proxy-port=${HTTP_PROXY_PORT}
      com.netflix.exhibitor.s3.proxy-username=${HTTP_PROXY_USERNAME}
      com.netflix.exhibitor.s3.proxy-password=${HTTP_PROXY_PASSWORD}
EOF

    HTTP_PROXY="--s3proxy=/opt/exhibitor/proxy.properties"
fi


exec 2>&1

# If we use exec and this is the docker entrypoint, Exhibitor fails to kill the ZK process on restart.
# If we use /bin/bash as the entrypoint and run wrapper.sh by hand, we do not see this behavior. I suspect
# some init or PID-related shenanigans, but I'm punting on further troubleshooting for now since dropping
# the "exec" fixes it.
#
# exec java -jar /opt/exhibitor/exhibitor.jar \
# 	--port 8181 --defaultconfig /opt/exhibitor/defaults.conf \
# 	--configtype s3 --s3config thefactory-exhibitor:${CLUSTER_ID} \
# 	--s3credentials /opt/exhibitor/credentials.properties \
# 	--s3region us-west-2 --s3backup true

java $EXHIBITOR_JVM_OPTS -jar /opt/exhibitor/exhibitor.jar \
  --port 8181 --defaultconfig /opt/exhibitor/defaults.conf \
  ${BACKUP_CONFIG} \
  ${HTTP_PROXY} \
  --hostname ${HOSTNAME} \
  ${SECURITY}
