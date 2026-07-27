# otterdog

![Version: 1.2.1][version-badge] <!-- x-release-please-version -->
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: 1.4.0](https://img.shields.io/badge/AppVersion-1.4.0-informational?style=flat-square)

An otterdog Web App Helm chart for Kubernetes

**Homepage:** <https://github.com/eclipse-csi/otterdog>

## Source Code

* <https://github.com/eclipse-csi/otterdog>
* <https://github.com/eclipse-csi/helm-charts>

## Requirements

Kubernetes: `>=1.23.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://eclipse-csi.github.io/helm-charts | ghproxy | 0.4.0 |
| oci://registry-1.docker.io/cloudpirates | mongodb | 0.18.1 |
| oci://registry-1.docker.io/cloudpirates | valkey | 0.24.3 |

## Installation

Add the Eclipse CSI Helm repository:

```console
helm repo add eclipse-csi https://eclipse-csi.github.io/helm-charts
helm repo update
```

Install the chart with the release name `otterdog`:

```console
helm install otterdog eclipse-csi/otterdog \
  --namespace otterdog --create-namespace
```

Provide your own configuration with a values file:

```console
helm install otterdog eclipse-csi/otterdog \
  --namespace otterdog --create-namespace \
  -f my-values.yaml
```

Or override individual values on the command line:

```console
helm install otterdog eclipse-csi/otterdog \
  --namespace otterdog --create-namespace \
  --set config.configOwner=MyOrg \
  --set github.appId=123456
```

Upgrade an existing release:

```console
helm upgrade otterdog eclipse-csi/otterdog \
  --namespace otterdog -f my-values.yaml
```

Uninstall the release:

```console
helm uninstall otterdog --namespace otterdog
```

> **Note:** the `mongodb`, `valkey` and `ghproxy` sub-charts are enabled by default,
> and the MongoDB, Valkey and ghproxy connection endpoints are auto-derived from the
> sub-chart service names — no manual host configuration is needed in the common case.
> Secrets must be supplied either through `values.yaml` or through Vault — see the
> [Secrets](#secrets) section below. See the [Values](#values) section for all options.

## Development mode

For local development you can run the chart entirely self-contained: no Vault, all
dependencies (MongoDB, Valkey, ghproxy) deployed by the sub-charts, and debug logging
enabled. Secrets are provided inline in your values file (dev only — never commit real
secrets).

Create a `dev-values.yaml`:

```yaml
# vault disabled → secrets come from this file
vault:
  enabled: false

config:
  # verbose logging
  debug: true
  configOwner: "MyOrg"
  configRepo: "otterdog-configs"
  configPath: "otterdog.json"
  configToken: "ghp_xxx"
  # mongoHost / mongoPort / valkeyUri / ghProxyUri are auto-derived from the
  # sub-chart services, so they can be left empty in dev.

github:
  appId: "123456"
  # PEM content of the GitHub App private key
  appPrivateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
  webhookSecret: "dev-webhook-secret"

# in-cluster dependencies (enabled by default, shown here for clarity)
mongodb:
  enabled: true
  auth:
    rootPassword: changeme
    appUserPassword: changeme
valkey:
  enabled: true
ghproxy:
  enabled: true
```

Install into a dev namespace:

```console
helm install otterdog eclipse-csi/otterdog \
  --namespace otterdog-dev --create-namespace \
  -f dev-values.yaml
```

Port-forward the service to reach the web app locally:

```console
kubectl -n otterdog-dev port-forward svc/otterdog 5000:5000
```

Then open <http://localhost:5000>.

To iterate quickly on chart changes, render the manifests without installing:

```console
helm template otterdog . -f dev-values.yaml | less
```

## Secrets

Secrets can be provided in two mutually exclusive ways, controlled by `vault.enabled`.

### Non-Vault mode (`vault.enabled: false`)

Secret values are read from `values.yaml` and rendered into dedicated Kubernetes
`Secret` objects by `templates/secrets.yaml`. This is intended for local/dev use only —
do not commit real secrets.

### Vault mode (`vault.enabled: true`)

Secrets are synced from HashiCorp Vault by the
[Vault Secrets Operator (VSO)](https://developer.hashicorp.com/vault/docs/platform/k8s/vso).
`templates/vault-static-secret.yaml` creates one `VaultStaticSecret` per secret, each syncing
into its own Kubernetes `Secret`.

All keys are read from a single Vault KV v2 entry:

```
<vault.secretMount>/data/<vault.secretPath>     e.g. csi/data/otterdog/dev
```

The following keys must exist in that Vault entry:

| Vault key | Kubernetes Secret (VSO destination) | Consumed as |
| --------- | ----------------------------------- | ----------- |
| `otterdog_config_token` | `<release>-config-token` | env `OTTERDOG_CONFIG_TOKEN` |
| `github_webhook_secret` | `<release>-webhook-secret` | env `GITHUB_WEBHOOK_SECRET` |
| `github_app_key` | `<release>-app-private-key` | file `/run/secrets/app-private-key/app.key` (env `GITHUB_APP_PRIVATE_KEY`) |
| `dependency_track_token` | `<release>-dependency-track-token` | env `DEPENDENCY_TRACK_TOKEN` |
| `mongodb_root_password` | `<release>-mongodb-root-credentials` | MongoDB subchart root password; also embedded in `MONGO_URI` when no `mongodb.customUsers` are configured |
| `mongodb_app_password` | `<release>-mongodb-app-credentials` (key `CUSTOM_PASSWORD`) and `<release>-mongo-uri` (env `MONGO_URI`) | MongoDB app user password |
| `valkey_password` | `<release>-valkey-credentials` | Valkey subchart password (used by the `valkey` sub-chart itself via `auth.existingSecret`/`auth.existingSecretPasswordKey`); only synced when `valkey.enabled` and `valkey.auth.enabled` |
| `valkey_password` | `<release>-valkey-uri` (env `REDIS_URI`) | Same password, embedded in the app's `REDIS_URI` when `valkey.auth.enabled`; when `valkey.auth.enabled: false`, `REDIS_URI` is still created but with no credentials |

Notes:

- `MONGO_URI` is built by one of three mutually exclusive `VaultStaticSecret` variants,
  selected automatically based on `mongodb.customUsers` / `mongodb.auth.enabled`:
  - `mongodb.customUsers` configured → uses `mongodb_app_password`, with
    `authSource=<mongodb.customUsers[0].database>` (default `otterdog`).
  - no `customUsers`, `mongodb.auth.enabled: true` → uses `mongodb_root_password`, with
    `authSource=admin` — MongoDB's root user always lives in the `admin` database,
    regardless of `config.mongoDatabase`.
  - `mongodb.auth.enabled: false` → no credentials at all in `MONGO_URI`.
- `mongodb_root_password` is also used by the MongoDB subchart to bootstrap the root user
  (and the app user, when `mongodb.customUsers` is configured).
- Similarly, `valkey_password` has two destinations: `<release>-valkey-credentials` bootstraps
  the Valkey server itself (subchart-consumed), while `<release>-valkey-uri` is what the
  otterdog app actually connects with (`REDIS_URI`) — keep both in sync if you rotate it
  manually instead of just updating the Vault value.
- Vault connection settings (auth path, role, mount and path) are configured under the
  `vault.*` values below.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `1` | Number of replicas to deploy |
| image.repository | string | `"ghcr.io/eclipse-csi/otterdog"` | Image repository |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.tag | string | `""` | Image tag (defaults to the chart appVersion if empty) |
| imagePullSecrets | list | `[]` | Image pull secrets |
| nameOverride | string | `""` | Name override for the chart |
| fullnameOverride | string | `""` | Full name override for the chart |
| config.debug | bool | `false` | Enable debug mode |
| config.baseUrl | string | `"http://0.0.0.0:5000"` | Base URL for the application |
| config.cacheControl | bool | `false` | Enable cache control |
| config.appRoot | string | `"/app/work"` | Application root directory |
| config.mongoHost | string | `""` | MongoDB host (optional — auto-derived: `<release>-mongodb.<namespace>.svc.cluster.local`) |
| config.mongoPort | string | `""` | MongoDB port (optional — auto-derived: `27017`) |
| config.mongoDatabase | string | `"otterdog"` | MongoDB database name |
| config.mongoUsername | string | `""` | MongoDB username for the auto-derived URI (optional; defaults to customUsers[0].name) |
| config.mongoPassword | string | `""` | MongoDB password for the auto-derived URI (optional; defaults to customUsers[0].password) |
| config.valkeyUri | string | `""` | Redis URI (optional — auto-derived: `redis://<release>-valkey.<namespace>.svc.cluster.local:6379`) |
| config.valkeyUsername | string | `""` | Redis/Valkey username for the auto-derived URI (optional; ignored when valkeyUri is set) |
| config.valkeyPassword | string | `""` | Redis/Valkey password for the auto-derived URI (optional; ignored when valkeyUri is set) |
| config.ghProxyUri | string | `""` | GitHub proxy URI (optional — auto-derived: `http://<release>-ghproxy.<namespace>.svc.cluster.local:8888`) |
| config.configOwner | string | `""` | GitHub organization hosting the otterdog.json, e.g. MyOrg (https://github.com/MyOrg) |
| config.configRepo | string | `".otterdog"` | GitHub repo hosting the otterdog.json, e.g. (https://github.com/MyOrg/.otterdog) |
| config.configPath | string | `"/app/otterdog.json"` | Path to the otterdog.json, e.g. otterdog.json |
| config.configToken | string | `""` | A valid GitHub token, no need for any permissions, just for rate limit purposes |
| config.dependencyTrackUrl | string | `""` | Dependency-Track URL |
| config.dependencyTrackToken | string | `""` | A valid Dependency-Track token, no need for any permissions, just for rate limit purposes |
| initJob.enabled | bool | `true` | Run a Helm post-install/post-upgrade hook Job that calls /internal/init (refreshes org configs, policies and blueprints) after every install/upgrade. |
| initJob.backoffLimit | int | `4` | Number of retries before the Job is considered failed |
| policies.enabled | bool | `true` | Enable the policy check CronJob |
| policies.schedule | string | `"*/5 * * * *"` | Cron schedule for the policy check |
| policies.batchSize | int | `10` | Number of checks per invocation |
| github.adminTeams | string | `"otterdog-admins"` | GitHub admin teams |
| github.webhookEndpoint | string | `"/github-webhook/receive\"\""` | GitHub webhook endpoint |
| github.webhookSecret | string | `""` | GitHub webhook secret |
| github.webhookValidationContext | string | `""` | GitHub webhook validation context |
| github.webhookSyncContext | string | `""` | GitHub webhook sync context |
| github.appId | string | `""` | GitHub app ID |
| github.appPrivateKey | string | `""` | GitHub app private key |
| vault.enabled | bool | `false` | Enable Vault Secrets Operator (VSO) integration for secrets |
| vault.tlsSkipVerify | bool | `true` | Skip TLS verification when connecting to Vault |
| vault.authPath | string | `""` | Vault Kubernetes auth path, e.g. auth/kubernetes-<instance>-<env>-<namespace> |
| vault.role | string | `""` | Vault role for authentication, e.g. <instance>-<env>_<namespace>_role |
| vault.secretMount | string | `"csi"` | Vault KV v2 secrets engine mount path, e.g. csi |
| vault.secretPath | string | `"otterdog/dev"` | Full path inside the mount, e.g. otterdog/<env> → csi/data/otterdog/staging |
| vault.serviceAccountName | string | `"secrets-manager-sa"` | Service account name for the Vault Kubernetes auth method (optional; defaults to "secrets-manager-sa") |
| vault.operator | object | `{"refreshAfter":"30s"}` | VSO operator configuration |
| vault.operator.refreshAfter | string | `"30s"` | How often VSO syncs the secret from Vault (e.g. 30s, 1m) |
| ingress.enabled | bool | `true` | Enable ingress |
| ingress.defaultBackend.enabled | bool | `false` | Enable default backend |
| ingress.className | string | `"nginx"` | Ingress class name |
| ingress.annotations | object | `{}` | Ingress annotations |
| ingress.hosts | list | `[{"host":"otterdog.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}]` | Ingress hosts |
| router.enabled | bool | `false` | Enable router (OpenShift Route) |
| router.tls.enabled | bool | `true` | Enable TLS termination on the route |
| router.tls.termination | string | `"edge"` | TLS termination type (edge, passthrough, reencrypt) |
| router.tls.insecureEdgeTerminationPolicy | string | `"Redirect"` | Behavior for insecure (HTTP) traffic on a TLS route |
| protectInit.path | string | `"/internal/"` | Path restricted to this dedicated Ingress/Route |
| protectInit.ingress.enabled | bool | `false` | Enable a dedicated Ingress restricted to protectInit.path |
| protectInit.ingress.className | string | `"nginx"` | Ingress class name |
| protectInit.ingress.annotations | object | `{}` | Ingress annotations (e.g. IP allowlist, auth) |
| protectInit.ingress.host | string | `"otterdog.local"` | Host for the dedicated Ingress |
| protectInit.router.enabled | bool | `false` | Enable a dedicated OpenShift Route restricted to protectInit.path |
| protectInit.router.host | string | `""` | Host for the dedicated Route (defaults to router.host when empty) |
| protectInit.router.annotations | object | `{}` | Route annotations (e.g. IP allowlist, auth) |
| protectInit.router.tls.enabled | bool | `true` | Enable TLS termination on the route |
| protectInit.router.tls.termination | string | `"edge"` | TLS termination type (edge, passthrough, reencrypt) |
| protectInit.router.tls.insecureEdgeTerminationPolicy | string | `"Redirect"` | Behavior for insecure (HTTP) traffic on a TLS route |
| service.type | string | `"NodePort"` | Service type |
| service.port | int | `5000` | Service port |
| serviceAccount.create | bool | `true` | Create a service account |
| serviceAccount.automount | bool | `true` | Automount the service account token |
| serviceAccount.annotations | object | `{}` | Service account annotations |
| serviceAccount.name | string | `""` | Service account name |
| podAnnotations | object | `{}` | Pod annotations |
| podLabels | object | `{}` | Pod labels |
| podSecurityContext | object | `{}` | Pod security context |
| securityContext | object | `{}` | Container security context |
| resources | object | `{}` | Resource requests and limits for the otterdog container |
| initContainers | list | `[]` | Override the default init containers (wait-for-mongodb, wait-for-redis) |
| autoscaling.enabled | bool | `false` | Enable Horizontal Pod Autoscaler |
| autoscaling.minReplicas | int | `1` | Minimum number of replicas |
| autoscaling.maxReplicas | int | `100` | Maximum number of replicas |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage |
| volumes | list | `[]` | Additional volumes on the output Deployment definition |
| volumeMounts | list | `[]` | Additional volumeMounts on the output Deployment definition |
| nodeSelector | object | `{}` | Node labels for pod assignment |
| tolerations | list | `[]` | Tolerations for pod assignment |
| affinity | object | `{}` | Affinity rules for pod assignment |
| startupProbe | object | `{"failureThreshold":24,"httpGet":{"path":"/internal/health","port":"http"},"initialDelaySeconds":5,"periodSeconds":5,"timeoutSeconds":3}` | Startup probe: gates liveness/readiness until the app is listening, so slow starts don't trigger "connection refused" failures or premature restarts. |
| startupProbe.httpGet.path | string | `"/internal/health"` | Startup probe path |
| startupProbe.httpGet.port | string | `"http"` | Startup probe port |
| startupProbe.initialDelaySeconds | int | `5` | Delay before the first startup check |
| startupProbe.periodSeconds | int | `5` | How often to probe during startup |
| startupProbe.timeoutSeconds | int | `3` | Probe timeout |
| startupProbe.failureThreshold | int | `24` | Failures allowed before the container is restarted (5s * 24 = up to 120s to start) |
| livenessProbe.httpGet.path | string | `"/internal/health"` | Liveness probe path |
| livenessProbe.httpGet.port | string | `"http"` | Liveness probe port |
| livenessProbe.periodSeconds | int | `15` | How often to probe |
| livenessProbe.timeoutSeconds | int | `3` | Probe timeout |
| livenessProbe.failureThreshold | int | `3` | Consecutive failures before the container is restarted |
| readinessProbe.httpGet.path | string | `"/internal/health"` | Readiness probe path |
| readinessProbe.httpGet.port | string | `"http"` | Readiness probe port |
| readinessProbe.initialDelaySeconds | int | `5` | Delay before the first readiness check |
| readinessProbe.periodSeconds | int | `10` | How often to probe |
| readinessProbe.timeoutSeconds | int | `3` | Probe timeout |
| readinessProbe.failureThreshold | int | `3` | Consecutive failures before the pod is marked unready |
| readinessProbe.successThreshold | int | `1` | Consecutive successes before the pod is marked ready |
| mongodb.enabled | bool | `true` | Enable MongoDB subchart (cloudpirates/mongodb OCI chart) |
| mongodb.auth.enabled | bool | `true` | Enable MongoDB authentication |
| mongodb.auth.rootUsername | string | `"root"` | MongoDB root username |
| mongodb.auth.rootPassword | string | `"changeme"` | MongoDB root password (set to "" when vault.enabled; the subchart uses this to bootstrap the app user) |
| mongodb.auth.existingSecret | string | `"{{ printf \"%s-mongodb-root-credentials\" .Release.Name }}"` |  |
| mongodb.auth.existingSecretPasswordKey | string | `"mongodb_root_password"` |  |
| mongodb.customUsers | list | `[{"database":"otterdog","existingSecret":"{{ printf \"%s-mongodb-app-credentials\" .Release.Name }}","name":"otterdog","password":"changeme","roles":["readWrite"],"secretKeys":{"database":"CUSTOM_DB","name":"CUSTOM_USER","password":"CUSTOM_PASSWORD"}}]` | Name of the K8s Secret holding the app user credentials for vault mode. Created by vault-static-secret.yaml when vault.enabled. Must match customUsers[0].existingSecret — set both to the same value. Non-vault mode: leave password set and existingSecret commented out. Vault mode: comment out password and uncomment existingSecret/secretKeys. |
| mongodb.persistence | object | `{"accessMode":"ReadWriteOnce","enabled":true,"size":"8Gi","storageClass":""}` | MongoDB persistence (PersistentVolumeClaim) configuration, passed to the mongodb subchart |
| mongodb.persistence.enabled | bool | `true` | Enable a PersistentVolumeClaim for MongoDB data |
| mongodb.persistence.storageClass | string | `""` | StorageClass for the PVC (empty = cluster default) |
| mongodb.persistence.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC |
| mongodb.persistence.size | string | `"8Gi"` | Size of the PVC |
| valkey.enabled | bool | `true` | Enable Valkey subchart (cloudpirates/valkey OCI chart) |
| valkey.auth.enabled | bool | `true` | Enable Valkey authentication |
| valkey.auth.password | string | `"changeme"` |  |
| valkey.persistence.enabled | bool | `true` |  |
| valkey.persistence.size | string | `"8Gi"` |  |
| valkey.persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| ghproxy.enabled | bool | `true` | Enable ghproxy |

<!-- x-release-please-start-version -->
[version-badge]: https://img.shields.io/badge/Version-1.2.1%2Dinformational?style=flat-square
<!-- x-release-please-end -->
