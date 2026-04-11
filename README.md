# Kubernetes Logging POC

A local proof-of-concept log pipeline running entirely on Minikube. Collects logs from pods, ships them to VictoriaLogs, and visualizes them in Grafana.

---

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│   sample-app    │────▶│   Fluent Bit    │────▶│  VictoriaLogs   │────▶│   Grafana   │
│  (namespace:    │     │  (DaemonSet,    │     │  (namespace:    │     │ (namespace: │
│   default)      │     │   namespace:    │     │   logging)      │     │  logging)   │
│                 │     │   logging)      │     │  port: 9428     │     │             │
└─────────────────┘     └─────────────────┘     └──────────────────┘     └─────────────┘
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| `minikube` | v1.32+ | https://minikube.sigs.k8s.io/docs/start/ |
| `kubectl` | v1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| `helm` | v3.12+ | https://helm.sh/docs/intro/install/ |
| `make` | any | pre-installed on macOS/Linux |

---

## Quick Start

```bash
make setup
```

That's it. Once complete, run:

```bash
make open-grafana
```

Login with `admin` / `admin123`.

---

## Step-by-Step Manual Setup

1. Start Minikube:
   ```bash
   minikube start
   ```

2. Create the `logging` namespace:
   ```bash
   kubectl apply -f k8s/namespace.yaml
   ```

3. Deploy VictoriaLogs:
   ```bash
   kubectl apply -f k8s/victorialogs/
   kubectl rollout status deployment/victorialogs --namespace logging --timeout=120s
   kubectl wait --namespace logging --for=condition=ready pod --selector=app=victorialogs --timeout=120s
   ```

4. Add Helm repos:
   ```bash
   helm repo add fluent https://fluent.github.io/helm-charts
   helm repo add grafana https://grafana.github.io/helm-charts
   helm repo update
   ```

5. Install Fluent Bit:
   ```bash
   helm upgrade --install fluent-bit fluent/fluent-bit \
     --namespace logging \
     --values k8s/fluentbit/values.yaml
   ```

6. Install Grafana:
   ```bash
   helm upgrade --install grafana grafana/grafana \
     --namespace logging \
     --values k8s/grafana/values.yaml
   ```

7. Deploy the sample app:
   ```bash
   kubectl apply -f k8s/sample-app/
   ```

---

## Accessing Grafana

Open Grafana via minikube:

```bash
make open-grafana
```

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `admin123` |

The VictoriaLogs datasource is provisioned automatically using the `victoriametrics-logs-datasource` Grafana plugin — no manual setup needed.

---

## Querying Logs

Navigate to Grafana → Explore → select the `VictoriaLogs` datasource → switch to **Code** mode.

VictoriaLogs uses LogsQL. Fluent Bit's kubernetes filter extracts metadata as top-level fields, so they're queryable directly without `| json`.

```logql
# All logs from the default namespace
{kubernetes.namespace_name="default"}

# Filter by log level (level is a top-level field, no | json needed)
{kubernetes.namespace_name="default"} level:error
{kubernetes.namespace_name="default"} level:warn

# Filter by app name
{kubernetes.namespace_name="default"} app:sample-app-2

# Combine filters
{kubernetes.namespace_name="default"} app:sample-app-2 level:error

# Filter by pod name
{kubernetes.namespace_name="default", kubernetes.pod_name=~"sample-app.*"}

# Search in message text
{kubernetes.namespace_name="default"} msg:db_connection_failed

# All logs from the logging namespace (Fluent Bit, Grafana, VictoriaLogs)
{kubernetes.namespace_name="logging"}

# All logs across the cluster
*
```

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make setup` | Full setup: start Minikube + deploy all components |
| `make start` | Start Minikube only |
| `make deploy` | Deploy all manifests and Helm releases |
| `make open-grafana` | Open Grafana in the browser via minikube service |
| `make open-victorialogs` | Port-forward VictoriaLogs UI to localhost:9428 |
| `make status` | Show pod status across all namespaces |
| `make logs-fluentbit` | Tail Fluent Bit pod logs |
| `make logs-app` | Tail sample-app pod logs |
| `make cleanup` | Delete all resources and stop Minikube |
| `make help` | Print all available targets |

---

## Cleanup

```bash
make cleanup
```

This removes all Helm releases, Kubernetes resources, and stops Minikube.

---

## Troubleshooting

**`kubectl wait` fails with "no matching resources found"**
- The pod hasn't been scheduled yet. The Makefile uses `kubectl rollout status` first to wait for scheduling before the readiness check.

**Pods stuck in `Pending` or `ContainerCreating`**
- First-time image pulls can take a few minutes on Minikube. Watch with `make status`.
- If stuck longer, check resources: `kubectl describe pod <pod-name> -n logging`
- Minikube may need more resources: `minikube start --cpus=4 --memory=4096`

**Grafana shows "No data" with `{namespace="default"}`**
- Use `{kubernetes.namespace_name="default"}` instead. Fluent Bit's kubernetes filter stores namespace under `kubernetes.namespace_name`, not `namespace`.
- Make sure you're in **Code** mode in the Explore query editor, not Builder mode.

**Grafana shows `missing _msg field` warning**
- Fluent Bit's kubernetes filter merges and drops the `log` field by default. The config uses `Keep_Log On` to preserve it so VictoriaLogs can map it to `_msg`.

**Grafana datasource error: `unsupported path /loki/api/v1/query_range`**
- VictoriaLogs is not fully Loki-compatible. The datasource must use the `victoriametrics-logs-datasource` plugin, not the built-in Loki datasource. This is already configured in `k8s/grafana/values.yaml`.

**`minikube service` hangs or doesn't open browser**
- Try: `minikube service grafana --namespace logging --url` and open the URL manually.

**Fluent Bit not shipping logs**
- Check Fluent Bit logs: `make logs-fluentbit`
- All lines should show `HTTP status=200`. Any other status means VictoriaLogs rejected the payload.
