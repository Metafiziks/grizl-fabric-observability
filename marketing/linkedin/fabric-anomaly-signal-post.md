# Supporting LinkedIn Post

I got tired of dashboards politely implying that production was haunted.

So I gave Microsoft Fabric a panic button.

Built a KQL-only anomaly-signal layer over Eventhouse `RawLogs` using `series_decompose_anomalies()`, wired it into Fabric Activator/Reflex, and made the incident webhook carry the actual useful stuff:

- anomaly score
- baseline
- actual value
- expected value
- service
- route
- deployment SHA
- error signature
- time window
- KQL function/query reference

The point is simple: if an alert is going to create a GitHub issue or summon Copilot, it should bring receipts.

Not "backend is sad."

"`/api/memes` is at 24% error rate, baseline is 1.5%, anomaly score is 2.91, deployment `abc1234` looks suspicious, here is the RawLogs evidence."

That is the kind of incident context an engineer, or a coding agent, can actually use.

Public sanitized package here:

https://github.com/Metafiziks/grizl-fabric-observability

No fake MLflow layer. No decorative notebooks. Just Fabric Eventhouse, KQL functions, Activator, GitHub issues, and anomaly signals with teeth.

Article below.

#MicrosoftFabric #KQL #Observability #AnomalyDetection #Azure #Copilot #DevOps #AIOps
