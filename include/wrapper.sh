#!/bin/bash -e

# Legend
# -Xms = -XX:InitialHeapSize
# -Xmx = -XX:MaxHeapSize)
# -Xmx2g -Xms2g 
DEFAULT_ZK_JAVA_INITIAL_HEAP_SIZE="-XX:InitialHeapSize=2g"
DEFAULT_ZK_JAVA_MAX_HEAP_SIZE="-XX:MaxHeapSize=2g"
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
: ${ZK_JAVA_INITIAL_HEAP_SIZE:=$DEFAULT_ZK_JAVA_INITIAL_HEAP_SIZE}
: ${ZK_JAVA_MAX_HEAP_SIZE:=$DEFAULT_ZK_JAVA_MAX_HEAP_SIZE}

# NOTE: ZK_JAVA_OPTS is an environment var we use to append several java cmdline flags together
# Enables printing of ergonomically selected JVM flags that appeared on the command line.
ZK_JAVA_OPTS="-XX:+PrintCommandLineFlags"
# Prints garbage collection output.
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintGC"
# Explain what caused garbage collection
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintGCCause"
# Prints garbage collection output along with time stamps.
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps"
#  instruct the Java process to print the time an application is actually running, 
# as well as the time the application was stopped due to GC events
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintGCApplicationConcurrentTime -XX:+PrintGCApplicationStoppedTime"
# With this flag we tell the JVM to print the age distribution of all objects contained 
# in the survivor spaces on each young generation GC.
# source: https://blog.codecentric.de/en/2012/08/useful-jvm-flags-part-5-young-generation-garbage-collection/
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintTenuringDistribution"
# With this flag, we get information on how G1 makes Ergonomic decisions.
# source: https://blogs.oracle.com/g1gc/entry/g1_gc_tuning_a_case
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+PrintAdaptiveSizePolicy"
# Pre-touch the Java heap during JVM initialization. 
# Every page of the heap is thus demand-zeroed during initialization rather 
# than incrementally during application execution.
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -XX:+AlwaysPreTouch"
# set java thread stack size
# source: https://www.mkyong.com/java/find-out-your-java-heap-memory-size/
ZK_JAVA_OPTS="$ZK_JAVA_OPTS -Xss512k"
# Set initial Java heap size
ZK_JAVA_OPTS="$ZK_JAVA_OPTS $ZK_JAVA_INITIAL_HEAP_SIZE"
# Set maximum Java heap size
ZK_JAVA_OPTS="$ZK_JAVA_OPTS $ZK_JAVA_MAX_HEAP_SIZE"

# HOSTNAME=`hostname --fqdn`
# IP=$(ping -c 1 "$HOSTNAME" | grep PING| cut -d' ' -f3| cut -d'(' -f2|cut -d')' -f1)

export EXHIBITOR_JVM_OPTS="-Xmx512m"
# NOTE: Options should look like this when done "-XX:+PrintCommandLineFlags -XX:+PrintGC -XX:+PrintGCCause -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCApplicationConcurrentTime -XX:+PrintGCApplicationStoppedTime -XX:+PrintTenuringDistribution -XX:+PrintAdaptiveSizePolicy -Xmx2g -Xms2g -XX:+AlwaysPreTouch -Xss512k"
export ZK_JVM_OPTS="$ZK_JAVA_OPTS"
# NOTE: This is set by default in zookeeper according to this 
# source: https://issues.apache.org/jira/browse/ZOOKEEPER-1670
# export SERVER_JVMFLAGS=""

# Generates the default exhibitor config and launches exhibitor
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
	zoo-cfg-extra=tickTime\=2000&initLimit\=10&syncLimit\=5&quorumListenOnAllIPs\=true&maxClientCnxns\=150
	auto-manage-instances-settling-period-ms=0
	auto-manage-instances=1
	auto-manage-instances-fixed-ensemble-size=$ZK_ENSEMBLE_SIZE
EOF

# Cat environment vars to /opt/zookeeper/conf/java.env
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
