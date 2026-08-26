# PiggyMetrics DevOps Assignment

Kind cluster + Jenkins CI/CD + blue-green deployment for
[PiggyMetrics](https://github.com/sqshq/piggymetrics).

## What's here
- `kind/kind-config.yaml` — 3-node Kind cluster
- `k8s/` — namespace, secrets, RabbitMQ, per-service MongoDB, config,
  registry, monitoring, turbine-stream-service, and blue/green
  Deployments + live/preview Services for the 5 business services
- `scripts/blue-green-switch.sh` — promotes a new image to the idle color,
  smoke-tests it, then atomically flips live traffic
- `scripts/rollback.sh` — instantly reverts to the previous color
- `jenkins/` — Jenkins Docker image, docker-compose, and one Jenkinsfile
  per business service

## Known deviations from the original repo (and why)
- `java:8-jre` base image in every service's Dockerfile is dead on Docker
  Hub — replaced with `eclipse-temurin:8-jre-jammy` (functionally identical).
- Build requires Java 8 specifically (Spring Boot 1.3.5 / Spring Cloud
  Brixton) even though the host may have a newer JDK installed.
- Health checks use `/health` (Spring Boot 1.x convention), not
  `/actuator/health` (Boot 2.x+).
- `/health` returns 401 without OAuth2 credentials — this is expected;
  our smoke test treats any real HTTP response as "service is alive."

## Setup

```bash
# 1. Cluster
kind create cluster --config kind/kind-config.yaml

# 2. Build all service images (Java 8 required)
cd ~/piggymetrics
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 mvn clean package -DskipTests
sed -i 's|^FROM java:8-jre|FROM eclipse-temurin:8-jre-jammy|' */Dockerfile
for svc in config registry gateway auth-service account-service statistics-service notification-service monitoring turbine-stream-service; do
  docker build -t piggymetrics-$svc:local ./$svc
done
docker build -t piggymetrics-mongodb:local ./mongodb

# 3. Load images into Kind
for img in config registry gateway auth-service account-service statistics-service notification-service monitoring turbine-stream-service mongodb; do
  kind load docker-image piggymetrics-$img:local --name piggymetrics
done

# 4. Deploy
cd ~/piggymetrics-devops
kubectl apply -f k8s-namespace.yaml
kubectl create secret generic piggymetrics-secrets -n piggymetrics \
  --from-literal=CONFIG_SERVICE_PASSWORD=password \
  --from-literal=MONGODB_PASSWORD=password \
  --from-literal=ACCOUNT_SERVICE_PASSWORD=password \
  --from-literal=STATISTICS_SERVICE_PASSWORD=password \
  --from-literal=NOTIFICATION_SERVICE_PASSWORD=password
kubectl apply -f k8s/
```

## Blue-green demo

```bash
scripts/blue-green-switch.sh account-service <tag> 1   # promote + switch
scripts/rollback.sh account-service                    # revert
```

See `docs/blue-green-strategy.md` for the full write-up.

## Endpoints (via kubectl port-forward)
- Gateway: `kubectl -n piggymetrics port-forward svc/gateway 8081:4000` → http://localhost:8081
- Eureka: `kubectl -n piggymetrics port-forward svc/registry 8761:8761` → http://localhost:8761
- RabbitMQ: `kubectl -n piggymetrics port-forward svc/rabbitmq 15672:15672` → http://localhost:15672 (guest/guest)
- Hystrix: `kubectl -n piggymetrics port-forward svc/monitoring 9000:9000` → http://localhost:9000/hystrix
  (stream URL: `http://turbine-stream-service:8989/turbine/turbine.stream`)

## Jenkins & Registry

docker run -d --restart=always -p 5000:5000 --name kind-registry registry:2
docker network connect kind kind-registry


sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
  {
   "insecure-registries": [
      "localhost:5000"
  ]
 }
 EOF
 sudo systemctl restart docker
 docker info | grep -A5 "Insecure Registries"
 docker exec piggymetrics-jenkins cat /var/jenkins_home/secrets/initialAdminPassword


```bash
cd jenkins
kind get kubeconfig --name piggymetrics --internal > ~/.kube/kind-piggymetrics-jenkins.config
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock) docker compose up -d --build
docker exec piggymetrics-jenkins cat /var/jenkins_home/secrets/initialAdminPassword

```
Open http://localhost:8082, create a Pipeline job per service pointing at
`jenkins/Jenkinsfile.<service>`.




For each of gateway, auth-service, account-service, statistics-service, notification-service: New Item → Pipeline → SCM: piggymetrics-devops repo → Script Path jenkins/Jenkinsfile.<service> → Build Now.

This is the step that actually makes the app work — each build compiles, dockerizes, pushes to the registry, and blue-green-deploys that service for real.
