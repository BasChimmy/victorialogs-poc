# How It All Works Together

This repo implements a complete log pipeline on a local Minikube Kubernetes cluster. Four components work together to generate, collect, store, and visualize logs.

## The Pipeline

```
Sample Apps  →  Fluent Bit  →  VictoriaLogs  →  Grafana
 (generate)     (collect)       (store)         (visualize)
```

## Components

### Sample Apps (log producers)

Two busybox-based deployments (`sample-app` and `sample-app-2`) run in the `default` namespace. Each pod runs a shell loop that writes structured JSON log lines to stdout every few seconds:

```json
{"level":"info","msg":"request_received from pod sample-app-xyz","time":"2026-04-09T12:00:00Z","app":"sample-app"}
```

- `sample-app` — 2 replicas, logs every 3s, simulates general app events (request_received, user_login, cache_miss, etc.)
- `sample-app-2` — 2 replicas, logs every 5s, simulates error-heavy scenarios (db_connection_failed, auth_token_expired, etc.)

These apps exist purely to generate realistic log traffic for the pipeline.

### Fluent Bit (log collector)

Fluent Bit is deployed as a DaemonSet via Helm into the `logging` namespace. It runs on every node and automatically tails container log files from the node's filesystem.

What it does:

1. Reads stdout/stderr logs from all containers on the node
2. Applies a `kubernetes` filter that enriches each log line with pod metadata (namespace, pod name, container name, labels)
3. Forwards everything to VictoriaLogs over HTTP using the `http` output plugin

The key config in `k8s/fluentbit/values.yaml`:

- The `kubernetes` filter merges the JSON log body into the top-level record and preserves the original `log` field (`Keep_Log On`) so VictoriaLogs can use it as the message field
- The `http` output sends logs to `victorialogs.logging.svc.cluster.local:9428` at the `/insert/jsonline` endpoint, telling VictoriaLogs which fields to use for stream identification (`kubernetes.namespace_name`, `kubernetes.pod_name`, `kubernetes.container_name`), message (`log`), and timestamp (`time`)

### VictoriaLogs (log storage)

VictoriaLogs is a lightweight log database deployed as a single-replica Deployment in the `logging` namespace. It receives log data from Fluent Bit over HTTP, indexes it, and stores it on disk.

- Runs on port `9428`, exposed internally via a `ClusterIP` Service
- Stores data in an `emptyDir` volume at `/vlogs-data` (ephemeral — data is lost if the pod restarts)
- Retains logs for 7 days (`-retentionPeriod=7d`)
- Provides a query API compatible with the VictoriaMetrics LogsQL language
- Also exposes a built-in web UI accessible via `make open-victorialogs` (port-forward to localhost:9428)

### Grafana (visualization)

Grafana is deployed via Helm into the `logging` namespace and serves as the dashboard and query interface.

- Exposed as a `NodePort` service so it can be opened from the host via `minikube service`
- Comes pre-configured with the `victoriametrics-logs-datasource` plugin and a provisioned datasource pointing at VictoriaLogs — no manual setup needed
- Default credentials: `admin` / `admin123`

To query logs, go to Explore, select the VictoriaLogs datasource, and use LogsQL:

```
{kubernetes.namespace_name="default"}
```

## How They Connect

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Minikube Cluster                                                        │
│                                                                          │
│  namespace: default              namespace: logging                      │
│  ┌──────────────┐               ┌──────────────┐                        │
│  │ sample-app   │──stdout──┐    │  Fluent Bit  │                        │
│  │ (2 replicas) │          │    │  (DaemonSet) │                        │
│  └──────────────┘          │    └──────┬───────┘                        │
│  ┌──────────────┐          │           │                                │
│  │ sample-app-2 │──stdout──┤    reads container    HTTP POST            │
│  │ (2 replicas) │          │    logs from node     /insert/jsonline     │
│  └──────────────┘          │    filesystem              │               │
│                            │           │                ▼               │
│                            └───────────┘    ┌──────────────────┐        │
│                                             │  VictoriaLogs    │        │
│                                             │  :9428           │        │
│                                             │  ClusterIP svc   │        │
│                                             └────────┬─────────┘        │
│                                                      │                  │
│                                               query API                 │
│                                                      │                  │
│                                                      ▼                  │
│                                             ┌──────────────────┐        │
│                                             │  Grafana         │        │
│                                             │  NodePort svc    │        │
│                                             └──────────────────┘        │
│                                                      │                  │
└──────────────────────────────────────────────────────┼──────────────────┘
                                                       │
                                                       ▼
                                                   Browser
```

1. Sample apps write JSON logs to stdout
2. Kubernetes stores those logs as container log files on each node
3. Fluent Bit (running on every node as a DaemonSet) tails those log files, enriches them with Kubernetes metadata, and POSTs them to VictoriaLogs
4. VictoriaLogs indexes and stores the logs, making them queryable via LogsQL
5. Grafana connects to VictoriaLogs as a datasource and lets you explore, search, and visualize the logs

## Deployment Order

The Makefile enforces this order via `make deploy`:

1. Create the `logging` namespace
2. Deploy VictoriaLogs and wait for it to be ready (Fluent Bit needs it as a destination)
3. Install Fluent Bit via Helm (starts collecting and forwarding immediately)
4. Install Grafana via Helm (datasource is auto-provisioned)
5. Deploy sample apps (logs start flowing through the pipeline)
