# GRIZL Fabric Observability

Sanitized Microsoft Fabric Eventhouse/KQL observability package for a Cloud Run or similar structured-log pipeline.

This repository contains only the public/shareable Fabric layer:

| Path | Purpose |
|---|---|
| `fabric/` | Fabric provisioning helpers, config templates, manifests, and dry-run-safe scripts |
| `kql/` | Eventhouse KQL views, dashboard queries, Activator alert queries, and anomaly-signal functions |
| `docs/fabric-incident-orchestrator.md` | Reference architecture for wiring Fabric Activator incidents to an external GitHub/Copilot remediation service |

No tenant secrets, Event Hubs connection strings, Fabric tokens, GitHub tokens, or live tenant IDs are included. Replace placeholder values such as `<FABRIC_TENANT_ID>`, `<FABRIC_WORKSPACE_ID>`, and `<FABRIC_EVENTHUB_NAME>` with values from your own tenant.

## What is included

The KQL artifacts assume a `RawLogs` Eventhouse table populated from structured application logs. The package provides:

- logical RawLogs views: `HttpRequests()`, `ApplicationErrors()`, `FrontendTelemetry()`, `Deployments()`, `ForwarderHealth()`
- dashboard tile queries for operational triage
- Activator/Reflex alert queries
- KQL-only anomaly signals using Eventhouse-native `series_decompose_anomalies()`

The anomaly-signal layer intentionally covers high-value production signals only:

| Function | Signal |
|---|---|
| `BackendHttpErrorRateAnomalies()` | backend 5xx/error-rate anomalies by service and route |
| `RouteLatencyAnomalies()` | route p95 latency anomalies when `durationMs` is available |
| `ErrorSignatureSpikeAnomalies()` | repeated application error-signature spikes |
| `ForwarderFreshnessDropAnomalies()` | drops in forwarder freshness/healthy event volume |
| `ForwarderDropFailureAnomalies()` | skipped-message/retry/nack/failure spikes |
| `PostDeploymentRegressionAnomalies()` | post-deployment regressions by `deploymentSha` |
| `GrizlRecentAnomalySignals()` | union query suitable for a single Activator trigger |

## Quick start

1. Copy the config template and fill in tenant-specific non-secret values:

   ```bash
   cp fabric/config/grizl.fabric.env.example fabric/config/grizl.fabric.env
   ```

2. Run local checks:

   ```bash
   npm run fabric:check
   ```

3. Dry-run the anomaly-signal Kusto management command:

   ```bash
   npm run fabric:kusto:anomaly-signals:dry-run
   ```

4. Apply KQL after reviewing the output and authenticating with an authorized Azure/Fabric identity:

   ```bash
   npm --prefix fabric run kusto:anomaly-signals
   ```

See `fabric/README.md` for provisioning details and `docs/fabric-incident-orchestrator.md` for the incident-enrichment flow.

## Security notes

- Do not commit `fabric/config/grizl.fabric.env`.
- Do not commit Event Hubs-compatible connection strings or SAS keys.
- Keep Fabric service-principal secrets, webhook secrets, and GitHub tokens in your secret manager.
- `fabric/scripts/check.sh` scans `fabric/` for Event Hubs connection-string material as a local guardrail.
