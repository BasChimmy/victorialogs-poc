# Project Requirement: Kubernetes Logging POC

## Overview

This project is a local proof-of-concept (POC) that demonstrates a full Kubernetes log pipeline using **Minikube**. The goal is to collect logs from pods, ship them to a log storage backend, and visualize them in a dashboard.

### Log Pipeline

```
App Pods → Fluent Bit → VictoriaLogs → Grafana
```

---

## Goals

- Spin up a working log pipeline entirely on a local Minikube cluster
- Use **Fluent Bit** as the log collector (DaemonSet)
- Use **VictoriaLogs** as the log storage backend
- Use **Grafana** as the visualization layer
- Deploy a **sample app** that generates structured logs for testing
- Provide a **Makefile** for easy setup and teardown
- Provide a clear **README.md** for anyone to follow

---

## Prerequisites

The following tools must be installed on the local machine before running this project:

| Tool | Purpose |
|------|---------|
| `minikube` | Local Kubernetes cluster |
| `kubectl` | Kubernetes CLI |
| `helm` | Kubernetes package manager |
| `make` | Run Makefile targets |

---

## Project Structure

```
.
├── Makefile
├── README.md
├── project-requirement.md
└── k8s/
    ├── namespace.yaml
    ├── victorialogs/
    │   └── values.yaml
    ├── fluentbit/
    │   └── values.yaml
    ├── grafana/
    │   └── values.yaml
    └── sample-app/
        └── deployment.yaml
```

---

## Components

### 1. Namespace

- All logging components (Fluent Bit, VictoriaLogs, Grafana) run in namespace: `logging`
- Sample app runs in namespace: `default`

---

### 2. VictoriaLogs

**Installation method:** Helm

```
helm repo: https://victoriametrics.github.io/helm-charts
chart: victoriametrics/victoria-logs-single
namespace: logging
release name: victorialogs
```

**Custom values (`k8s/victorialogs/values.yaml`)**

- `server.retentionPeriod`: `7d`
- `server.persistentVolume.enabled`: `false` (emptyDir — ephemeral storage)

**Service name (internal):** `victorialogs-victoria-logs-single-server.logging.svc.cluster.local:9428`

---

### 3. Fluent Bit

**Installation method:** Helm

```
helm repo: https://fluent.github.io/helm-charts
chart: fluent/fluent-bit
namespace: logging
release name: fluent-bit
```

**Custom values (`k8s/fluentbit/values.yaml`)**

Output plugin:
- Type: `http`
- Match: `*`
- Host: `victorialogs-victoria-logs-single-server.logging.svc.cluster.local`
- Port: `9428`
- URI: `/insert/jsonline?_stream_fields=namespace,pod,container&_msg_field=log&_time_field=time`
- Format: `json_lines`
- Json_date_key: `time`
- Json_date_format: `iso8601`

Filter plugin:
- Type: `kubernetes`
- Match: `kube.*`
- Merge_Log: `On`
- Keep_Log: `Off`
- K8S-Logging.Parser: `On`
- K8S-Logging.Exclude: `On`

---

### 4. Grafana

**Installation method:** Helm

```
helm repo: https://grafana.github.io/helm-charts
chart: grafana/grafana
namespace: logging
release name: grafana
```

**Custom values (`k8s/grafana/values.yaml`)**

- Admin password: `admin123`
- Service type: `NodePort`
- Datasource (provisioned automatically):
  - Name: `VictoriaLogs`
  - Type: `loki` *(VictoriaLogs is Loki-API compatible)*
  - URL: `http://victorialogs-victoria-logs-single-server.logging.svc.cluster.local:9428`
  - Access: `proxy`
  - isDefault: `true`

---

### 5. Sample App

**Purpose:** Generate continuous structured logs so there is real data to query in Grafana.

**Deployment**
- Name: `sample-app`
- Namespace: `default`
- Replicas: `2`
- Image: `busybox`
- Command: shell loop that prints a JSON log line every 3 seconds

**Log format (stdout):**
```json
{"level":"info","msg":"hello from pod <HOSTNAME>","time":"<ISO8601_TIMESTAMP>"}
```

---

## Makefile Targets

The Makefile must include the following targets:

| Target | Description |
|--------|-------------|
| `make setup` | Full setup: start Minikube + deploy all components |
| `make start` | Start Minikube only (if already configured) |
| `make deploy` | Deploy all Kubernetes manifests and Helm releases |
| `make open-grafana` | Open Grafana in the browser via minikube service |
| `make open-victorialogs` | Port-forward VictoriaLogs UI to localhost:9428 |
| `make status` | Show pod status across all namespaces |
| `make logs-fluentbit` | Tail Fluent Bit pod logs |
| `make logs-app` | Tail sample-app pod logs |
| `make cleanup` | Delete all resources and stop Minikube |
| `make help` | Print all available targets with descriptions |

### Setup order in `make deploy`:
1. Apply `k8s/namespace.yaml`
2. Add Helm repos (fluent, grafana, victoriametrics) and update
3. Install VictoriaLogs via Helm and wait for StatefulSet to be ready
4. Install Fluent Bit with custom values
5. Install Grafana with custom values
6. Apply `k8s/sample-app/`
7. Print access instructions

---

## README.md Requirements

The README must include:

1. **Project title and short description**
2. **Architecture diagram** (ASCII)
3. **Prerequisites** section with tool versions
4. **Quick Start** section (just run `make setup`)
5. **Step-by-step manual setup** (for reference)
6. **How to access Grafana** (URL, credentials)
7. **How to query logs** with example LogQL/LogsQL queries
8. **Makefile targets** table
9. **Cleanup** instructions
10. **Troubleshooting** section covering common issues

---

## Acceptance Criteria

- [ ] `make setup` runs end-to-end without manual steps
- [ ] All pods reach `Running` state
- [ ] Fluent Bit ships logs to VictoriaLogs (no errors in Fluent Bit logs)
- [ ] Grafana datasource connects to VictoriaLogs successfully
- [ ] Querying `{namespace="default"}` in Grafana shows sample-app logs
- [ ] `make cleanup` removes all resources cleanly

---

## Notes for Kiro

- Generate all YAML files under `k8s/` as described in the structure
- Generate the `Makefile` with all targets listed above
- Generate `README.md` following the requirements above
- Use `kubectl wait` with `--timeout=120s` for readiness checks in the Makefile
- Helm repos should be added and updated before install in the Makefile
- The Grafana datasource should be provisioned automatically via Helm values (no manual UI steps required for datasource setup)
- All `make` targets should print a short description of what they are doing before running