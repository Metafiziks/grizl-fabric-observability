# Part V: I Gave Microsoft Fabric a Panic Button and Taught It to File GitHub Issues

Subtitle: A completely unreasonable tour through Fabric Eventhouse, KQL anomaly detection, Activator webhooks, and why your observability stack should stop politely blinking red and start bringing receipts.

---

I have developed a new philosophy of production monitoring:

If the system is on fire, I do not want a dashboard.

I want a **witness statement**.

I want the incident to arrive with fingerprints, timestamps, the deployment SHA, the suspicious route, the baseline it betrayed, the actual value that committed the crime, and enough context for a coding agent to open the repo and say, "unfortunately, yes, this does appear to be your fault."

So I built that.

Not a lab demo. Not a notebook cosplay situation. Not "AI observability" where the intelligence is a chart with a gradient and a dream.

I built a Fabric ML-observability signal layer that sits on top of real telemetry, detects useful anomalies with KQL, sends those anomaly fields through Fabric Activator, creates GitHub issues, and gives Copilot the evidence instead of a vague shrug.

The public sanitized package is here:

https://github.com/Metafiziks/grizl-fabric-observability

## The problem: dashboards are where incidents go to perform theater

Dashboards are useful.

Dashboards are also liars by omission.

They show you that something is wrong, then immediately make you perform archaeology:

- Is this route always this bad?
- Did this start after a deploy?
- Is this one error type or a zoo?
- Is the log forwarder dead, or is production actually quiet?
- Is the current value weird, or just Monday?
- Which repo owns this mess?

That is not incident response.

That is asking a firefighter to first build a weather station.

What I wanted was a layer that said:

> "The backend HTTP error rate for `/api/memes` is 24%. Its baseline is 1.5%. The anomaly score is 2.91. This is tied to deployment `abc1234`. Here is the KQL function that detected it. Here are the dimensions. Here is the GitHub issue. Here is the evidence prompt. Good luck, carbon-based deployer."

That is the vibe.

## The architecture: boring plumbing, violent usefulness

The pipeline is intentionally practical:

1. Apps emit structured logs.
2. Cloud logging routes them to a forwarder.
3. The forwarder lands them in Microsoft Fabric Eventstream.
4. Eventstream writes to Eventhouse `RawLogs`.
5. KQL functions shape RawLogs into useful views.
6. KQL anomaly functions detect high-value failure modes.
7. Fabric Activator/Reflex calls an incident webhook.
8. The backend creates a GitHub issue and, when policy allows, assigns Copilot.

The key decision: **do not invent fake ML when KQL has the right hammer.**

Fabric Eventhouse already gives us time-series operators. The anomaly layer uses `series_decompose_anomalies()` directly over `RawLogs`.

No MLflow.
No model registry.
No ornamental notebook with a confused pickle file.
No pipeline named `final_final_actually_final.ipynb`.

Just KQL, deployable functions, and an operator-editable layer people can understand at 2:13 AM.

## What signals made the cut

I deliberately did not build 400 alerts, because that is how teams create a distributed denial-of-sleep attack against themselves.

The layer covers only the signals that are worth waking up for:

### 1. Backend HTTP error-rate anomalies

Grouped by service and route.

Because "the backend is broken" is not a diagnosis. "`/api/memes` just betrayed its baseline" is a diagnosis.

Outputs include:

- `signalName`
- `anomalyScore`
- `baseline`
- `actual`
- `expected`
- `service`
- `route`
- `timeWindowStart`
- `timeWindowEnd`
- `kqlFunction`
- `kqlQueryRef`

### 2. Route latency anomalies

If `durationMs` exists, we use it.

If it does not, the function returns no rows like a grown adult. No hallucinated latency. No "maybe the vibes were slow."

### 3. Error-signature spikes

Repeated signatures are where the bodies are buried.

`MongoTimeoutError:/api/memes` tells a much better story than "ERROR count increased."

### 4. Forwarder freshness/drop anomalies

Observability systems deserve observability too.

If your log forwarder gets stale, starts skipping messages, retries forever, or starts making weird noises in the basement, that is not a dashboard footnote. That is an incident precursor.

### 5. Post-deployment regressions by deployment SHA

Every deployment gets one sacred right:

The right to be blamed accurately.

This signal correlates error-rate anomalies to recent `deploymentSha` values so the incident can show whether the new build arrived wearing muddy boots.

## The incident issue should be evidence, not vibes

The backend orchestrator now recognizes optional anomaly fields from Activator payloads:

- `signalName`
- `anomalyScore`
- `baseline`
- `actual`
- `expected`
- `timeWindowStart`
- `timeWindowEnd`
- `dimensions`
- `kqlFunction`
- `kqlQueryRef`

If Activator sends them, they show up in the GitHub issue and in the evidence prompt.

If Activator does not send them, nothing breaks.

That part matters. Observability pipelines should degrade gracefully. An incident system that explodes because one optional field is missing is not an incident system. It is a second incident wearing a badge.

## Why this matters for Copilot remediation

Coding agents are only as useful as the context you hand them.

If you assign Copilot an issue that says:

> "Backend alert fired."

you deserve the PR you get.

If you assign Copilot an issue that says:

> "Backend HTTP error rate anomaly. Service: grizl-backend. Route: `/api/memes`. Actual: 0.24. Baseline: 0.015. Deployment SHA: abc1234. Error signature: MongoTimeoutError:/api/memes. Evidence from RawLogs attached. KQL reference included."

Now we are talking.

That is not magic. That is basic respect for the future agent reading your mess.

The orchestrator still uses policy gates. Not every alert should summon a coding agent from the walls. Forwarder freshness issues are operational. Unscoped alerts need humans. Low-severity weirdness can sit down and wait its turn.

But scoped application failures with route, signature, deployment SHA, and evidence?

Open the issue. Assign the agent. Make production explain itself.

## What I published

I split the sanitized Fabric layer into a public standalone repo:

https://github.com/Metafiziks/grizl-fabric-observability

It includes:

- Fabric provisioning helpers
- config templates
- KQL logical views
- dashboard queries
- Activator alert queries
- anomaly-signal functions
- docs for the incident workflow
- dry-run-friendly scripts
- no live tenant IDs
- no Event Hubs connection strings
- no Fabric tokens
- no GitHub tokens

The anomaly function set:

- `BackendHttpErrorRateAnomalies()`
- `RouteLatencyAnomalies()`
- `ErrorSignatureSpikeAnomalies()`
- `ForwarderFreshnessDropAnomalies()`
- `ForwarderDropFailureAnomalies()`
- `PostDeploymentRegressionAnomalies()`
- `GrizlRecentAnomalySignals()`

## The takeaway

The future of AI-assisted ops is not "ask a chatbot why prod is sad."

The future is:

- telemetry with structure
- anomaly detection close to the data
- incident payloads with numeric evidence
- GitHub issues that read like a forensic report
- coding agents receiving enough context to do useful work
- policy gates so automation does not sprint into traffic

Dashboards tell you where to look.

This tells the incident what to say when it arrives.

That is the difference between observability and observability with teeth.

And yes, the system can now snitch on production in full sentences.

Good.
