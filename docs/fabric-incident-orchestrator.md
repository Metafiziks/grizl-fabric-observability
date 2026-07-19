# Fabric Incident Orchestrator

The Fabric Incident Orchestrator is the backend action layer between Microsoft Fabric Activator/Reflex alerts and the GRIZL GitHub/Copilot remediation flow.

```text
Fabric Activator / Reflex alert
  -> POST /api/fabric/incidents
  -> Fabric Data Agent MCP evidence query
  -> GitHub issue in the mapped repository
  -> policy-gated Copilot Coding Agent issue assignment
```

The separation of concerns is intentional:

| Layer | Responsibility |
|---|---|
| Fabric Data Agent | Read-only evidence over `RawLogs` and KQL functions |
| Backend orchestrator | Payload validation, policy, repo mapping, issue creation, Copilot handoff |
| Copilot Coding Agent | Code remediation only after policy says the incident is safe/scoped/code-actionable |

## Webhook endpoint

Configure Fabric Activator/Reflex to call:

```text
POST https://<backend-host>/api/fabric/incidents
```

Use one of these authentication headers:

```http
Authorization: Bearer <FABRIC_ALERT_WEBHOOK_SECRET>
```

or:

```http
x-grizl-fabric-secret: <FABRIC_ALERT_WEBHOOK_SECRET>
```

The route rejects requests when `FABRIC_ALERT_WEBHOOK_SECRET` is missing, the shared secret is wrong, JSON is invalid, or the payload exceeds `FABRIC_ALERT_MAX_PAYLOAD_BYTES` (default 64 KB).

## Environment variables

```dotenv
FABRIC_INCIDENT_ORCHESTRATOR_ENABLED=true
FABRIC_ALERT_WEBHOOK_SECRET=<shared-webhook-secret>
FABRIC_ALERT_MAX_PAYLOAD_BYTES=65536

FABRIC_MCP_WORKSPACE_ID=<fabric-workspace-id>
FABRIC_MCP_DATA_AGENT_ID=<fabric-data-agent-id>
FABRIC_MCP_TOOL_NAME=DataAgent_grizl_incident_evidence_agent
FABRIC_TENANT_ID=<entra-tenant-id>
FABRIC_CLIENT_ID=<entra-app-client-id>
FABRIC_CLIENT_SECRET=<entra-app-client-secret>
FABRIC_MCP_SCOPE=https://api.fabric.microsoft.com/.default
# Optional local smoke-test override:
FABRIC_MCP_BEARER_TOKEN=<short-lived-fabric-token>
FABRIC_KQL_QUERY_SERVICE_URI=https://<cluster>.<region>.kusto.fabric.microsoft.com
FABRIC_KQL_DATABASE_NAME=grizl-house
FABRIC_KQL_RAW_TABLE_NAME=RawLogs
FABRIC_KUSTO_SCOPE=https://api.kusto.windows.net/.default

GITHUB_TOKEN=<github-token-with-issues-write>
GITHUB_REPO=<github-owner>/<backend-repo>
FABRIC_INCIDENT_REPO_MAP_JSON={"grizl-backend":"<github-owner>/<backend-repo>","grizl-frontend":"<github-owner>/<frontend-repo>","grizl-log-forwarder":"<github-owner>/<backend-repo>"}

# Native GitHub Copilot coding agent handoff. Assigning an issue to Copilot
# creates a pull request when the repository/organization has the feature enabled.
COPILOT_CODING_AGENT_ASSIGNMENT_ENABLED=true
COPILOT_CODING_AGENT_ASSIGNEE=Copilot
COPILOT_CODING_AGENT_ASSIGNEE_NODE_ID=<COPILOT_CODING_AGENT_ASSIGNEE_NODE_ID>
# Optional webhook fallback for non-native integrations.
COPILOT_CODING_AGENT_WEBHOOK_URL=
COPILOT_CODING_AGENT_WEBHOOK_TOKEN=
```

Production Fabric MCP auth should use an Entra service principal. Grant the app the required Fabric API permissions, enable service-principal access in the Fabric tenant if required, and add it to the Fabric workspace with enough access to query the Data Agent. `FABRIC_MCP_BEARER_TOKEN` remains available as a local smoke-test override. Do not commit Fabric tokens, service-principal secrets, or Event Hubs connection strings.

## GitHub Actions / Cloud Run deployment

The main Cloud Run deploy workflow wires the orchestrator through repository variables and GCP Secret Manager, matching the existing forwarder deployment pattern.

Set these GitHub repository variables before enabling production alerts:

```text
FABRIC_INCIDENT_ORCHESTRATOR_ENABLED=true
FABRIC_ALERT_MAX_PAYLOAD_BYTES=65536
FABRIC_MCP_WORKSPACE_ID=<fabric-workspace-id>
FABRIC_MCP_DATA_AGENT_ID=<fabric-data-agent-id>
FABRIC_MCP_TOOL_NAME=DataAgent_grizl_incident_evidence_agent
FABRIC_TENANT_ID=<entra-tenant-id>
FABRIC_CLIENT_ID=<entra-app-client-id>
FABRIC_MCP_SCOPE=https://api.fabric.microsoft.com/.default
FABRIC_KQL_QUERY_SERVICE_URI=https://<cluster>.<region>.kusto.fabric.microsoft.com
FABRIC_KQL_DATABASE_NAME=grizl-house
FABRIC_KQL_RAW_TABLE_NAME=RawLogs
FABRIC_KUSTO_SCOPE=https://api.kusto.windows.net/.default
FABRIC_INCIDENT_REPO_MAP_JSON={"grizl-backend":"<github-owner>/<backend-repo>","grizl-frontend":"<github-owner>/<frontend-repo>","grizl-log-forwarder":"<github-owner>/<backend-repo>"}
COPILOT_CODING_AGENT_ASSIGNMENT_ENABLED=true
COPILOT_CODING_AGENT_ASSIGNEE=Copilot
COPILOT_CODING_AGENT_ASSIGNEE_NODE_ID=<COPILOT_CODING_AGENT_ASSIGNEE_NODE_ID>
COPILOT_CODING_AGENT_WEBHOOK_URL=<optional-handoff-endpoint>
```

Create or rotate these GCP Secret Manager secrets in the deploy project:

```text
FABRIC_ALERT_WEBHOOK_SECRET
FABRIC_CLIENT_SECRET
GITHUB_TOKEN
```

`GITHUB_TOKEN` must be a GitHub token or app installation token that can create and assign issues in every repository referenced by `FABRIC_INCIDENT_REPO_MAP_JSON`. `FABRIC_CLIENT_SECRET` is the Entra app secret used to mint Fabric API tokens at runtime. The optional `COPILOT_CODING_AGENT_WEBHOOK_URL` can stay unset when native issue assignment is enabled.

The service principal also needs Kusto database viewer access because the orchestrator falls back to direct RawLogs queries when the Data Agent runtime cannot access its datasource:

```kusto
.add database ['grizl-house'] viewers ('aadapp=<FABRIC_CLIENT_ID>;<FABRIC_TENANT_ID>') 'GRIZL Fabric incident orchestrator service principal'
```

## KQL anomaly-signal layer

The production ML-observability layer is KQL-only and lives in [`../kql/grizl-anomaly-signals.kql`](../kql/grizl-anomaly-signals.kql). It uses Eventhouse-native `series_decompose_anomalies()` over `RawLogs` through the existing logical views and avoids separate MLflow/model-registry assets.

Apply it after the base `RawLogs` views exist:

```bash
npm --prefix fabric run kusto:anomaly-signals:dry-run
npm --prefix fabric run kusto:anomaly-signals
```

High-value Activator functions:

| Function | Purpose |
|---|---|
| `BackendHttpErrorRateAnomalies()` | service/route 5xx error-rate anomalies |
| `RouteLatencyAnomalies()` | route p95 latency anomalies when `durationMs` is populated |
| `ErrorSignatureSpikeAnomalies()` | repeated error-signature spikes |
| `ForwarderFreshnessDropAnomalies()` | forwarder freshness/drop anomalies |
| `ForwarderDropFailureAnomalies()` | forwarder skipped/retry/nack/failure spikes |
| `PostDeploymentRegressionAnomalies()` | post-deploy service error-rate regressions by `deploymentSha` |
| `GrizlRecentAnomalySignals()` | union query for a single Activator trigger |

Configure Activator/Reflex to include these optional columns in webhook payloads when present: `signalName`, `anomalyScore`, `baseline`, `actual`, `expected`, `timeWindowStart`, `timeWindowEnd`, `dimensions`, `kqlFunction`, and `kqlQueryRef`. The orchestrator preserves existing alert payloads and enriches GitHub issues/Copilot handoff context only when these fields are present.

## Synthetic webhook smoke payload

```bash
curl -X POST "https://<backend-host>/api/fabric/incidents" \
  -H "Content-Type: application/json" \
  -H "x-grizl-fabric-secret: <FABRIC_ALERT_WEBHOOK_SECRET>" \
  -d '{
    "alertName": "Backend HTTP Error Spike",
    "severity": "ERROR",
    "service": "grizl-backend",
    "route": "/api/memes",
    "deploymentSha": "abc1234",
    "errorType": "MongoTimeoutError",
    "errorSignature": "MongoTimeoutError:/api/memes",
    "query": "HttpRequests() | where statusCode >= 500",
    "signalName": "backend_http_error_rate",
    "anomalyScore": 2.91,
    "baseline": 0.015,
    "actual": 0.24,
    "expected": 0.015,
    "kqlFunction": "BackendHttpErrorRateAnomalies",
    "kqlQueryRef": "kql/grizl-anomaly-signals.kql#BackendHttpErrorRateAnomalies",
    "dimensions": {
      "service": "grizl-backend",
      "route": "/api/memes"
    },
    "timeWindow": {
      "start": "2026-07-19T19:00:00Z",
      "end": "2026-07-19T19:10:00Z"
    }
  }'
```

Expected result: a `202 Accepted` response with the normalized incident summary, created issue, policy decision, and `copilotAction`.

## Policy and Copilot handoff

The orchestrator creates a GitHub issue for every accepted Fabric incident. It only considers Copilot handoff when all of these are true:

1. The anomaly type is code-actionable (`APPLICATION_ERROR`, `FRONTEND_API_ERROR_SPIKE`, `HIGH_LATENCY`, or `POST_DEPLOYMENT_ERROR`).
2. The incident has scope (`route`, `page`, `errorSignature`, or `deploymentSha`).
3. The service/source maps to a repository.
4. Evidence contains code-actionable signal.
5. Active remediation guardrails do not conflict.

If safe and `COPILOT_CODING_AGENT_ASSIGNMENT_ENABLED` is not `false`, the orchestrator assigns the GitHub issue to `COPILOT_CODING_AGENT_ASSIGNEE` (default `Copilot`). GitHub Copilot coding agent creates a pull request from issue assignment when enabled for the repository/organization.

Copilot is a GitHub App assignee (`github.com/apps/copilot-swe-agent`), not a normal repository user. The orchestrator uses GitHub GraphQL `addAssigneesToAssignable` with `COPILOT_CODING_AGENT_ASSIGNEE_NODE_ID` because the REST issue-assignee endpoint can return success without persisting the Copilot app assignment.

If issue assignment is disabled and `COPILOT_CODING_AGENT_WEBHOOK_URL` is not configured, the issue records:

```text
copilotAction.status = pending_configuration
```

If unsafe or unscoped, the issue records:

```text
copilotAction.status = skipped
```

The backend never reports `assigned` unless native Copilot issue assignment persists or a configured Copilot Coding Agent handoff endpoint returns success.

## Fabric Data Agent evidence

The MCP client calls:

```text
POST https://api.fabric.microsoft.com/v1/mcp/workspaces/{workspaceId}/dataagents/{dataAgentId}/agent
```

It first runs `tools/list` to infer the published tool input schema unless `FABRIC_MCP_TOOL_NAME` is set, then runs `tools/call` with the question field required by that schema. Live validation of the GRIZL agent currently requires `userQuestion`:

```json
{
  "userQuestion": "incident-specific evidence prompt"
}
```

Live validation showed the published Data Agent could answer a synthetic incident for `MongoTimeoutError:/api/memes`, identify route `/api/memes`, and return deployment `abc1234` from `RawLogs`. This evidence is embedded in the GitHub issue; the Data Agent does not create issues or perform remediation.

If the Data Agent MCP call is available but returns an internal datasource/authentication failure, the orchestrator runs a direct Kusto RawLogs fallback using the same service principal and embeds that evidence under `Direct Kusto Evidence Fallback`.

## Known limitations

- The service-principal path requires tenant/admin setup outside this repo: Fabric tenant settings, API permissions, workspace access, and GCP Secret Manager rotation for `FABRIC_CLIENT_SECRET`.
- Event Hubs-compatible connection strings for Eventstream custom endpoints are still captured through the Fabric UI and rotated into GCP Secret Manager.
- Copilot Coding Agent assignment depends on GitHub Copilot coding agent being enabled for the repository/organization and the runtime `GITHUB_TOKEN` having permission to assign issues.
