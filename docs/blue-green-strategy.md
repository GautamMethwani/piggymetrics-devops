# Blue-Green Deployment Strategy

## Scope
Applied to the 5 stateless business services: gateway, auth-service,
account-service, statistics-service, notification-service. Infra services
(config, registry, rabbitmq, monitoring, turbine, mongo) are single
Deployments — they change rarely and everything else depends on them.

## Mechanism
Each service has `<svc>-blue` and `<svc>-green` Deployments (identical
specs, `color` label differs), a live `<svc>` Service (selector = active
color — this is the ONLY thing real traffic hits), and a `<svc>-preview`
Service (selector = idle color, for testing before go-live).

## Release flow (scripts/blue-green-switch.sh)
1. Read live Service's selector -> active color
2. Load new image, update idle Deployment's image, scale it up
3. Wait for rollout / readiness probes to pass — abort (scale idle back to
   0) if they never do; production is never touched
4. Point `-preview` at idle color, run a smoke test (any real HTTP
   response = alive; only a connection failure counts as "down" here,
   since `/health` requires OAuth2 and correctly returns 401)
5. Only if smoke test passes: patch the live Service's selector to idle
   color — this is a single atomic operation, no split traffic window
6. Scale old color to 0 (kept warm, not deleted, for instant rollback)

## Rollback (scripts/rollback.sh)
1. Identify bad (current live) and good (previous) color
2. Scale good color back up if it's at 0, wait for readiness
3. Patch live Service back to good color
4. Scale bad color to 0

Verified working end-to-end on a live Kind cluster: account-service was
switched blue->green with a new build, then rolled back green->blue,
confirmed via `kubectl get svc account-service -o jsonpath='{.spec.selector.color}'`
at each step.


    traffic --> Service (live, selector: color=X)
                      |
          +-----------+-----------+
          |                       |
  Deployment: blue         Deployment: green
  (replicas: N if X=blue)  (replicas: 0 if idle)
                                   ^
                                   | smoke test only
                        Service (preview, selector: color=Y)

## Diagram
