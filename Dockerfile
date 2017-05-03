FROM ubuntu:xenial
MAINTAINER Mike Babineau michael.babineau@gmail.com

ENV \
    LANG=C.UTF-8 \
    ZK_RELEASE="http://www.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz" \
    EXHIBITOR_POM="https://raw.githubusercontent.com/Netflix/exhibitor/d911a16d704bbe790d84bbacc655ef050c1f5806/exhibitor-standalone/src/main/resources/buildscripts/standalone/maven/pom.xml" \
    JVMTOP_RELEASE="https://github.com/patric-r/jvmtop/releases/download/0.8.0/jvmtop-0.8.0.tar.gz" \
    DEBIAN_FRONTEND=noninteractive

# Workaround for bug: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=807948
RUN chmod 0777 /tmp

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/bash'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_VERSION=8u121
ENV JAVA_UBUNTU_VERSION=8u121-b13-0ubuntu1.16.04.2

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION=20160321

# Use one step so we can remove intermediate dependencies and minimize size
RUN set -ex \
    # security updates
    && apt-get update -q \
    && grep security /etc/apt/sources.list > /tmp/security.list \
    && apt-get upgrade -oDir::Etc::Sourcelist=/tmp/security.list -yq \
    && rm /tmp/security.list \
    # Install dependencies
    && apt-get install -y --no-install-recommends \
            wget \
            ca-certificates \
            procps \
    && apt-get install -y --no-install-recommends --auto-remove -oAPT::Install-Suggests=no \
       openjdk-8-jdk="$JAVA_UBUNTU_VERSION" \
	   ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
    && apt-get install -y --no-install-recommends --auto-remove -oAPT::Install-Suggests=no \
       maven \
    && grep '^networkaddress.cache.ttl=' /etc/java-8-openjdk/security/java.security || echo 'networkaddress.cache.ttl=60' >> /etc/java-8-openjdk/security/java.security \
    && [ "$JAVA_HOME" = "$(docker-java-home)" ] \
    # source: https://askubuntu.com/questions/599105/using-alternatives-with-java-7-and-java-8-on-14-04-2-lts
    # note: ignore error: update-java-alternatives: plugin alternative does not exist: /usr/lib/jvm/java-8-openjdk-amd64/jre/lib/amd64/IcedTeaPlugin.so
    # (Ignore the error at the end; IceaTea 8 isn't ready yet.)
    && update-java-alternatives -s /usr/lib/jvm/java-1.8.0-openjdk-amd64 \
    # see CA_CERTIFICATES_JAVA_VERSION notes above
    && /var/lib/dpkg/info/ca-certificates-java.postinst configure \
    
    # Install jvmtop
    && wget -O /tmp/jvmtop.gz "${JVMTOP_RELEASE}" \
    && mkdir -p /opt/jvmtop \
    && tar -xvzf /tmp/jvmtop.gz -C /opt/jvmtop \
    && chmod +x /opt/jvmtop/jvmtop.sh \
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
    && apt-get purge -y --auto-remove maven openjdk-9* \
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

EXPOSE 2181 2888 3888 8181

ENTRYPOINT ["bash", "-ex", "/opt/exhibitor/wrapper.sh"]

