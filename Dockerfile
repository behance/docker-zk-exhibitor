FROM ubuntu:xenial
MAINTAINER Mike Babineau michael.babineau@gmail.com

ENV \
    ZK_RELEASE="http://www.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz" \
    EXHIBITOR_POM="https://raw.githubusercontent.com/Netflix/exhibitor/d911a16d704bbe790d84bbacc655ef050c1f5806/exhibitor-standalone/src/main/resources/buildscripts/standalone/maven/pom.xml" \
    JVMTOP_RELEASE="https://github.com/patric-r/jvmtop/releases/download/0.8.0/jvmtop-0.8.0.tar.gz" \
    # Append "+" to ensure the package doesn't get purged
    BUILD_DEPS="oracle-java8-installer oracle-java8-set-default maven" \
    DEBIAN_FRONTEND=noninteractive

# Workaround for bug: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=807948
RUN chmod 0777 /tmp

# Use one step so we can remove intermediate dependencies and minimize size
RUN set -ex \
    # Install dependencies
    && apt-get update -q \
    && apt-get upgrade -yqq \
    && apt-get install -y --no-install-recommends \
    		tcl \
    		tk \
            wget \
            curl \
            ca-certificates \
            procps \
    && apt-get install -y --force-yes software-properties-common python-software-properties \
    # && /bin/echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections \
    && /bin/echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | debconf-set-selections \
    && add-apt-repository -y ppa:webupd8team/java \
    && apt-get update \
    && apt-get install -y $BUILD_DEPS \

    # Default DNS cache TTL is -1. DNS records, like, change, man.
    # && grep '^networkaddress.cache.ttl=' /etc/java-7-openjdk/security/java.security || echo 'networkaddress.cache.ttl=60' >> /etc/java-7-openjdk/security/java.security \

    # Install jvmtop
    && wget -O /tmp/jvmtop.gz "${JVMTOP_RELEASE}" \
    && mkdir -p /opt/jvmtop \
    && tar -xvzf /tmp/jvmtop.gz -C /opt/jvmtop --strip=1 \
    && rm /tmp/jvmtop.gz \

    # Install ZK
    && wget -O /tmp/zookeeper.tgz "${ZK_RELEASE}" \
    && mkdir -p /opt/zookeeper/transactions /opt/zookeeper/snapshots \
    && tar -xzf /tmp/zookeeper.tgz -C /opt/zookeeper --strip=1 \
    && rm /tmp/zookeeper.tgz \

    # Install Exhibitor
    && mkdir -p /opt/exhibitor \
    && wget -O /opt/exhibitor/pom.xml "${EXHIBITOR_POM}" \
    && mvn -f /opt/exhibitor/pom.xml package \
    && ln -s /opt/exhibitor/target/exhibitor*jar /opt/exhibitor/exhibitor.jar \

    # Remove build-time dependencies
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/{cache,log}/ \
    && rm -rf /var/lib/apt/lists/*.lz4 \

    # Send zk output to stdout
    && ln -sf /dev/stdout /opt/zookeeper/zookeeper.out

# Add the wrapper script to setup configs and exec exhibitor
ADD include/wrapper.sh /opt/exhibitor/wrapper.sh

# Add the optional web.xml for authentication
ADD include/web.xml /opt/exhibitor/web.xml

USER root
WORKDIR /opt/exhibitor

# Define commonly used JAVA_HOME variable
ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

EXPOSE 2181 2888 3888 8181

ENTRYPOINT ["bash", "-ex", "/opt/exhibitor/wrapper.sh"]

