# GRIZL Fabric provisioning package

This package is the repo-owned handoff point for recreating the current GRIZL Microsoft Fabric observability stack and for experimenting with a Fabric Data Agent over Eventhouse/KQL evidence.

It is intentionally conservative: resources with stable Fabric REST API paths have scripts, while tenant-specific item definitions that are not available from this worktree are represented as export/import scaffolding with explicit TODO markers instead of fabricated JSON.

For the backend action loop from Fabric alerts to GitHub issues/Copilot handoff, see [`../docs/fabric-incident-orchestrator.md`](../docs/fabric-incident-orchestrator.md).

## Current observability stack

```text
grizl-frontend browser telemetry
  -> grizl-backend /api/telemetry + backend structured stdout logs
  -> GCP Cloud Logging sink
  -> Pub/Sub topic grizl-log-events
  -> grizl-log-forwarder Cloud Run service
  -> Fabric Eventstream grizl-events / GRIZL-Source
  -> Eventhouse grizl-house / KQL database grizl-house / RawLogs
  -> KQL functions, dashboard tiles, Activator/Reflex alerts
```

The current manual Fabric resources and non-secret identifiers are captured in [`manifests/manual-resources.json`](./manifests/manual-resources.json). KQL remains source-of-truth in the repo root:

| Source | Purpose |
|---|---|
| [`../kql/grizl-observability.kql`](../kql/grizl-observability.kql) | RawLogs analytics and logical function definitions |
| [`../kql/grizl-dashboard-tiles.kql`](../kql/grizl-dashboard-tiles.kql) | Real-Time Dashboard tile queries |
| [`../kql/grizl-activator-alerts.kql`](../kql/grizl-activator-alerts.kql) | Activator/Reflex alert queries |
| [`../kql/grizl-anomaly-signals.kql`](../kql/grizl-anomaly-signals.kql) | KQL time-series anomaly signal functions for Activator/incident enrichment |

## Prerequisites

1. Install the Microsoft Fabric CLI package:

   ```bash
   pip install ms-fabric-cli
   fab --help
   ```

2. Authenticate to the target tenant:

   ```bash
   fab auth login
   ```

3. Copy and edit the non-secret config file:

   ```bash
   cp fabric/config/grizl.fabric.env.example fabric/config/grizl.fabric.env
   ```

Do not put Event Hubs connection strings, SAS keys, Fabric tokens, or other credentials in config files or manifests.

## Local validation

These checks do not require live Fabric authentication:

```bash
npm run fabric:check
# or
npm --prefix fabric run check
```

The check script runs `bash -n` over package scripts, parses JSON manifests, verifies referenced KQL files exist, and scans `fabric/` for committed Event Hubs connection string material.

## Preflight with Fabric auth

```bash
npm --prefix fabric run preflight
```

Preflight fails clearly when `fab` is missing, the CLI is not authenticated, or required non-secret config values are absent.

## Provision workflow

Always dry-run first:

```bash
npm --prefix fabric run provision:dry-run
```

Run live only after reviewing the dry-run output:

```bash
bash fabric/scripts/provision.sh --all --yes
```

The provision script can create the resources that have direct REST scaffolding:

| Target | Command flag | Notes |
|---|---|---|
| Workspace | `--workspace` | Uses `POST /v1/workspaces` with `FABRIC_WORKSPACE_NAME`. Capture the returned ID and set `FABRIC_WORKSPACE_ID`. |
| Eventhouse | `--eventhouse` | Requires `FABRIC_WORKSPACE_ID`; uses the configured `FABRIC_EVENTHOUSE_NAME`. |
| KQL database | `--kql-database` | Requires `FABRIC_WORKSPACE_ID`; apply table/function KQL from `../kql/grizl-observability.kql` after creation. |
| Eventstream shell | `--eventstream` | Creates the item shell only. The `GRIZL-Source` Event Hubs-compatible source and routing to `RawLogs` remain export-first/manual until a verified item definition is captured. |
| Data Agent | `--data-agent` | Creates a shell Data Agent; configure staging datasources/settings/few-shots separately. Requires paid supported Fabric capacity. |

Dashboard and Reflex/Activator item definitions are not faked. The repo source of truth remains the KQL files listed above until stable Fabric export/import definitions are captured from the tenant.

## Export/import path

After authenticating and setting `FABRIC_WORKSPACE_ID`, export live workspace metadata:

```bash
bash fabric/scripts/export-items.sh --yes
```

The export is written under `fabric/exports/<timestamp>/`. Review it before committing anything. Use the exported `items.json` to fill in item IDs in `fabric/config/grizl.fabric.env`, then replace TODO manifests only with verified Fabric definitions. If item IDs are configured, the export script also calls `items/{id}/getDefinition` for each item and stores the definition beside `items.json`.

### Eventstream definition import and remap

Live testing confirmed that Eventstream definitions can be retrieved with `items/{eventstreamId}/getDefinition`. The definition includes `eventstream.json`, `eventstreamProperties.json`, and `.platform` parts. A shell Eventstream has empty `sources` and `destinations`; an exported manual Eventstream can include the `GRIZL-Source` `CustomEndpoint` source and an `Eventhouse` destination with `workspaceId`, `itemId`, `tableName`, `connectionName`, and `mappingRuleName`.

To import a verified exported definition into a fresh workspace and remap the Eventhouse destination to the target KQL database:

```bash
bash fabric/scripts/import-eventstream-definition.sh \
  --definition fabric/exports/<timestamp>/eventstream-definition.json \
  --dry-run

bash fabric/scripts/import-eventstream-definition.sh \
  --definition fabric/exports/<timestamp>/eventstream-definition.json \
  --yes
```

The script rewrites Eventhouse destination `workspaceId`, `itemId`, and `tableName` using `FABRIC_WORKSPACE_ID`, `FABRIC_KQL_DATABASE_ID`, and `FABRIC_KQL_RAW_TABLE_NAME`, then calls `items/{eventstreamId}/updateDefinition`.

> **Connection string limitation:** Live API probes did not expose the Event Hubs-compatible custom endpoint secret/connection string through public endpoints. The source/routing definition can be imported, but the Event Hubs-compatible connection string still needs Fabric UI capture and GCP Secret Manager rotation unless a supported API is found.

## Teardown workflow

Teardown deletes only item IDs explicitly provided in `fabric/config/grizl.fabric.env`.

```bash
npm --prefix fabric run teardown:dry-run
bash fabric/scripts/teardown.sh --yes
```

Workspace deletion is skipped unless `FABRIC_DELETE_WORKSPACE=true` is set. This prevents accidental removal of shared/manual Fabric workspaces.

## Fabric Data Agent path

Fabric Data Agent can help replace the notebook/Foundry analytics layer for incident evidence Q&A over Eventhouse/KQL:

- Suitable: "Which deployment SHA correlates with the new 5xx spike?", "Show recent frontend API errors by page", "Is the forwarder stale?", "Summarize repeated error signatures from RawLogs."
- Not a full replacement: GitHub issue creation, assignment, Copilot session orchestration, and remediation execution still need an external orchestrator such as the existing remediation agent layer.

Public REST creation is available at:

```text
POST https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/dataAgents
```

After publish, the runtime MCP endpoint format is:

```text
https://api.fabric.microsoft.com/v1/mcp/workspaces/{WorkspaceId}/dataagents/{DataAgentId}/agent
```

This repo includes [`manifests/data-agent.payload.todo.json`](./manifests/data-agent.payload.todo.json) as a definition placeholder, but live creation should start with a shell agent. `fabric/scripts/create-data-agent.sh` creates that shell from `FABRIC_DATA_AGENT_NAME` and `FABRIC_DATA_AGENT_DESCRIPTION` unless `FABRIC_DATA_AGENT_PAYLOAD` points at a tenant-verified create payload.

### Data Agent staging workflow

Live testing confirmed that Data Agent definitions are available through `dataAgents/{dataAgentId}/getDefinition` / `updateDefinition` and include `Files/Config/data_agent.json`, `Files/Config/draft/stage_config.json`, and `.platform` parts. The staged configuration is easier to automate through these public management endpoints:

1. Create a shell agent with `POST workspaces/{workspaceId}/dataAgents` and `{ "displayName": "...", "description": "..." }`.
2. Configure staging settings with `GET/PATCH workspaces/{workspaceId}/dataAgents/{dataAgentId}/staging/settings`.
3. Add the KQL database as a Fabric item datasource:
   ```json
   {
     "type": "FabricItem",
     "itemReference": {
       "referenceType": "ById",
       "itemId": "<KQLDatabase item id>",
       "workspaceId": "<workspace id>"
     }
   }
   ```
4. Select table/function elements through `GET/PATCH .../staging/datasources/{datasourceId}/elements?rootId=<rootId>&id=<elementId>`.
5. Add few-shots with `POST .../staging/datasources/{datasourceId}/fewshots` and wait for them to become valid.
6. Publish with `POST .../staging/publish`.
7. Verify the MCP runtime at `mcp/workspaces/{workspaceId}/dataagents/{dataAgentId}/agent` with JSON-RPC `tools/list` and `tools/call`.

The helper script wraps these staging endpoints:

```bash
# Patch instructions.
bash fabric/scripts/data-agent-staging.sh settings-patch \
  --body fabric/manifests/data-agent-settings.example.json \
  --dry-run

# Add the configured KQLDatabase as a FabricItem datasource.
bash fabric/scripts/data-agent-staging.sh datasource-add --dry-run

# Add few-shots after FABRIC_DATA_AGENT_DATASOURCE_ID is known.
bash fabric/scripts/data-agent-staging.sh fewshots-post \
  --datasource-id <datasource-id> \
  --body fabric/manifests/data-agent-fewshots.example.json \
  --dry-run

# Publish staging to runtime.
bash fabric/scripts/data-agent-staging.sh publish --dry-run
```

The intended GRIZL datasource selection is `RawLogs` plus `HttpRequests`, `ApplicationErrors`, `FrontendTelemetry`, `Deployments`, and `ForwarderHealth`.

### Data Agent MCP runtime smoke test

The published MCP endpoint accepts JSON-RPC. `tools/list` should expose a read-only tool named from the Data Agent display name, and `tools/call` can answer against `RawLogs` and the selected functions.

```bash
curl -sS "https://api.fabric.microsoft.com/v1/mcp/workspaces/${FABRIC_WORKSPACE_ID}/dataagents/${FABRIC_DATA_AGENT_ID}/agent" \
  -H "Authorization: Bearer <fabric-token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

curl -sS "https://api.fabric.microsoft.com/v1/mcp/workspaces/${FABRIC_WORKSPACE_ID}/dataagents/${FABRIC_DATA_AGENT_ID}/agent" \
  -H "Authorization: Bearer <fabric-token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"<tool-name-from-tools-list>","arguments":{"userQuestion":"Find evidence for MongoTimeoutError on /api/memes and identify the related deployment SHA."}}}'
```

Live validation used synthetic `RawLogs` rows and confirmed that the published agent could answer an incident prompt for `MongoTimeoutError:/api/memes`, including the affected route and deployment SHA. Treat this as a smoke-test pattern; do not leave synthetic rows unlabeled in production analytics.

### Capacity and cost guidance

Data Agent requires a paid supported Fabric capacity, such as F2+ Fabric capacity or compatible Premium capacity. The lowest-cost testing path is F2 pay-as-you-go: start capacity for experiments, create/publish/test the agent, then pause capacity when not in use. Confirm tenant settings and permissions before running live scripts.

### Troubleshooting F2 workspace assignment

Assigning an existing trial workspace to F2 capacity can fail with `PowerBICapacityFoldersMigrationGenericArtifactsMigrationNotAllowedException`. If that happens, create a fresh F2-backed workspace for the Data Agent/provisioning test, then export/copy verified definitions from the existing workspace instead of trying to migrate it in place.

This was the successful live validation pattern: a clean F2-backed workspace was created after trial-workspace migration failed, then Eventhouse, KQL database, Eventstream, and Data Agent resources were recreated/imported there. The Data Agent was configured with the KQL datasource, selected `RawLogs` plus five functions, validated few-shots, published, and queried successfully over MCP.

## Mapping Fabric outputs back to GCP

Keep the GCP log sink, Pub/Sub topic/subscription, and Cloud Run forwarder intact. Fabric setup produces the Event Hubs-compatible source values that the existing forwarder consumes:

| Fabric output | Where it goes |
|---|---|
| Event Hub-compatible connection string primary key | GCP Secret Manager secret `FABRIC_EVENTHUB_CONNECTION_STRING` |
| Event Hub entity name (`<FABRIC_EVENTHUB_NAME>`) | Cloud Run env var `FABRIC_EVENTHUB_NAME` / GitHub variable |
| SAS key name (`<FABRIC_EVENTHUB_SHARED_ACCESS_KEY_NAME>`) | Cloud Run env var `FABRIC_EVENTHUB_SHARED_ACCESS_KEY_NAME` / GitHub variable |
| Protocol | `FABRIC_EVENTSTREAM_PROTOCOL=eventhub` |

Create or rotate the secret without putting the value in shell history:

```bash
printf '%s' '<connection-string-primary-key>' | \
  gcloud secrets versions add FABRIC_EVENTHUB_CONNECTION_STRING \
    --data-file=- \
    --project=<GCP_PROJECT_ID>
```

The deployed forwarder already reads the secret as the `FABRIC_EVENTHUB_CONNECTION_STRING` environment variable.

## Kusto management commands

`RawLogs` and the logical KQL functions can be created through the Eventhouse Kusto management endpoint after the KQL database exists. Use an access token for the Kusto resource, not the Fabric management resource:

```bash
KUSTO_TOKEN="$(az account get-access-token \
  --resource https://api.kusto.windows.net \
  --query accessToken \
  --output tsv)"

curl -sS "${FABRIC_KQL_QUERY_SERVICE_URI}/v1/rest/mgmt" \
  -H "Authorization: Bearer ${KUSTO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"db":"'"${FABRIC_KQL_DATABASE_NAME}"'","csl":".create table RawLogs (...)"}'
```

Use the full `RawLogs` DDL from [`../docs/observability.md`](../docs/observability.md), the `.create-or-alter function` blocks from [`../kql/grizl-observability.kql`](../kql/grizl-observability.kql), and the anomaly-signal database script in [`../kql/grizl-anomaly-signals.kql`](../kql/grizl-anomaly-signals.kql). For validation or demos, `.ingest inline into table RawLogs <| ...` can seed synthetic rows; remove or clearly label synthetic data before production dashboards and alerts are tuned.

The repo helper wraps the same endpoint:

```bash
# Dry-run command shape.
npm --prefix fabric run kusto:show-tables:dry-run

# Live smoke check after az login and config are set.
bash fabric/scripts/kusto-mgmt.sh --command '.show tables' --yes

# Apply a single management command from a file.
bash fabric/scripts/kusto-mgmt.sh --file /path/to/rawlogs.create.kql --yes

# Dry-run/apply the KQL-only anomaly signal layer.
npm --prefix fabric run kusto:anomaly-signals:dry-run
npm --prefix fabric run kusto:anomaly-signals
```

Recommended setup order:

1. Create `RawLogs` with Kusto management command text from `docs/observability.md`.
2. Create `HttpRequests`, `ApplicationErrors`, `FrontendTelemetry`, `Deployments`, and `ForwarderHealth` with the `.create-or-alter function` blocks from `kql/grizl-observability.kql`.
3. Create `BackendHttpErrorRateAnomalies`, `RouteLatencyAnomalies`, `ErrorSignatureSpikeAnomalies`, `ForwarderFreshnessDropAnomalies`, `ForwarderDropFailureAnomalies`, `PostDeploymentRegressionAnomalies`, and `GrizlRecentAnomalySignals` from `kql/grizl-anomaly-signals.kql`.
4. Optionally seed smoke rows with `.ingest inline into table RawLogs <| ...`.
5. Validate with direct KQL queries before selecting the table/functions in the Data Agent or Activator triggers.

### KQL anomaly-signal layer

The anomaly layer uses Eventhouse-native `series_decompose_anomalies()` over existing `RawLogs` telemetry. It intentionally covers only high-value production signals:

| Function | Signal |
|---|---|
| `BackendHttpErrorRateAnomalies()` | 5xx/error-rate anomalies by service and route |
| `RouteLatencyAnomalies()` | route p95 latency anomalies when `durationMs` is populated; returns no rows if latency is unavailable |
| `ErrorSignatureSpikeAnomalies()` | grouped application error-signature spikes |
| `ForwarderFreshnessDropAnomalies()` | negative anomalies in forwarder healthy event volume |
| `ForwarderDropFailureAnomalies()` | skipped-message/retry/nack/failure spikes |
| `PostDeploymentRegressionAnomalies()` | service error-rate anomalies correlated to recent `deploymentSha` values |
| `GrizlRecentAnomalySignals()` | Activator-friendly union of the above signals |

Each function projects Activator/webhook-friendly columns including `signalName`, `anomalyScore`, `baseline`, `actual`, `expected`, `timeWindowStart`, `timeWindowEnd`, `dimensions`, `kqlFunction`, and `kqlQueryRef`. Configure Activator to send those columns in the incident webhook so GitHub issues and Copilot prompts include the anomaly context.
