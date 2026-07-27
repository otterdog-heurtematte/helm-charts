# ghproxy

![Version: 0.4.1][version-badge] <!-- x-release-please-version -->
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)
![AppVersion: v20251030-0e4d5be42](https://img.shields.io/badge/AppVersion-v20251030--0e4d5be42-informational?style=flat-square)

A Helm chart for ghproxy

## Installation

`ghproxy` is a [caching reverse proxy for the GitHub API](https://github.com/kubernetes/test-infra/tree/master/ghproxy),
backed by Redis/Valkey. It is deployed as a stand-alone chart, or as a sub-chart
dependency of the `otterdog` chart.

Add the Eclipse CSI Helm repository:

```console
helm repo add eclipse-csi https://eclipse-csi.github.io/helm-charts
helm repo update
```

Install the chart with the release name `ghproxy`:

```console
helm install ghproxy eclipse-csi/ghproxy \
  --namespace ghproxy --create-namespace
```

Provide your own configuration with a values file:

```console
helm install ghproxy eclipse-csi/ghproxy \
  --namespace ghproxy --create-namespace \
  -f my-values.yaml
```

Or override individual values on the command line:

```console
helm install ghproxy eclipse-csi/ghproxy \
  --namespace ghproxy --create-namespace \
  --set redisAddress=my-redis:6379 \
  --set throttlingTimeMs=50
```

Upgrade an existing release:

```console
helm upgrade ghproxy eclipse-csi/ghproxy \
  --namespace ghproxy -f my-values.yaml
```

Uninstall the release:

```console
helm uninstall ghproxy --namespace ghproxy
```

> **Note:** ghproxy needs a Redis/Valkey instance to cache against. If none is deployed
> alongside it (e.g. when installed standalone, without the otterdog parent chart's
> `valkey` sub-chart), set `redisAddress` explicitly. See the [Secrets](#secrets) section
> below for how the Redis password is supplied, and the [Values](#values) section for all
> other options.

## Secrets

The only secret this chart manages is the Redis/Valkey password, supplied in one of two
mutually exclusive ways, controlled by `vault.enabled`.

### Non-Vault mode (`vault.enabled: false`)

`redisPassword` is read from `values.yaml` and rendered into a `<release>-redis-auth`
Kubernetes `Secret` by `templates/secret.yaml`. This is intended for local/dev use only —
do not commit real secrets. Leave `redisPassword` empty to run against an unauthenticated
Redis/Valkey instance (no secret/volume is mounted in that case).

### Vault mode (`vault.enabled: true`)

The password is synced from HashiCorp Vault by the
[Vault Secrets Operator (VSO)](https://developer.hashicorp.com/vault/docs/platform/k8s/vso).
`templates/vault-static-secret.yaml` creates a `VaultAuth` and a `VaultStaticSecret` that
syncs into the `<release>-redis-auth` Kubernetes `Secret`.

The key is read from a single Vault KV v2 entry:

```
<vault.secretMount>/data/<vault.secretPath>     e.g. csi/data/otterdog/dev
```

| Vault key | Kubernetes Secret (VSO destination) | Consumed as |
| --------- | ----------------------------------- | ----------- |
| `valkey_password` | `<release>-redis-auth` (key `redis-password`) | file `/etc/ghproxy-redis/redis-password` (arg `--redis-secret-file`) |

Notes:

- `vault.serviceAccountName` (default `secrets-manager-sa`) is the Kubernetes
  **ServiceAccount used to authenticate the `VaultAuth` login**.
- Vault connection settings (`vault.authPath`, `vault.role`, `vault.secretMount`,
  `vault.secretPath`) must match a Kubernetes auth role in Vault that authorizes
  `vault.serviceAccountName` in this release's namespace.
- `redisUsername` defaults to `"default"` whenever a password is in use (`redisPassword`
  set or `vault.enabled: true`) and no explicit username is given — matching Redis/Valkey's
  own default ACL user name.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.repository | string | `"us-docker.pkg.dev/k8s-infra-prow/images/ghproxy"` |  |
| image.tag | string | `"v20251030-0e4d5be42"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| redisAddress | string | `""` |  |
| redisUsername | string | `""` |  |
| redisPassword | string | `"changeme"` |  |
| legacyDisableDiskCachePartitionsByAuthHeader | bool | `false` |  |
| throttlingTimeMs | int | `10` |  |
| getThrottlingTimeMs | int | `10` |  |
| logLevel | string | `"info"` |  |
| extraArgs | list | `[]` |  |
| service.port | int | `8888` |  |
| persistence.enabled | bool | `true` |  |
| persistence.mountPath | string | `"/cache/"` |  |
| persistence.size | string | `"1Gi"` |  |
| persistence.storageClassName | string | `""` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.name | string | `""` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| vault.enabled | bool | `false` | Enable Vault Secrets Operator (VSO) integration for the redis-password secret |
| vault.authPath | string | `""` | Vault Kubernetes auth path, e.g. auth/kubernetes-<instance>-<env>-<namespace> |
| vault.role | string | `""` | Vault role for authentication, e.g. <instance>-<env>_<namespace>_role |
| vault.secretMount | string | `"csi"` | Vault KV v2 secrets engine mount path, e.g. csi |
| vault.secretPath | string | `"otterdog/dev"` | Full path inside the mount, e.g. otterdog/<env> → csi/data/otterdog/staging |
| vault.serviceAccountName | string | `"secrets-manager-sa"` | Service account name for the Vault Kubernetes auth method (optional; defaults to "secrets-manager-sa") |
| vault.operator | object | `{"refreshAfter":"30s"}` | VSO operator configuration |
| vault.operator.refreshAfter | string | `"30s"` | How often VSO syncs the secret from Vault (e.g. 30s, 1m) |

<!-- x-release-please-start-version -->
[version-badge]: https://img.shields.io/badge/Version-0.4.1%2Dinformational?style=flat-square
<!-- x-release-please-end -->
