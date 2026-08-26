FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      apt-transport-https ca-certificates curl gnupg lsb-release maven git \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64" \
    && chmod +x /usr/local/bin/kind \
    && curl -Lo /tmp/jdk8.tar.gz "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u422-b05/OpenJDK8U-jdk_x64_linux_hotspot_8u422b05.tar.gz" \
    && mkdir -p /opt/java8 && tar -xzf /tmp/jdk8.tar.gz -C /opt/java8 --strip-components=1 \
    && rm -rf /var/lib/apt/lists/* /tmp/jdk8.tar.gz
ARG DOCKER_GID=999
RUN groupadd -g ${DOCKER_GID} docker || true && usermod -aG docker jenkins
ENV JAVA8_HOME=/opt/java8
USER jenkins
RUN jenkins-plugin-cli --plugins workflow-aggregator git docker-workflow kubernetes-cli pipeline-utility-steps timestamper
