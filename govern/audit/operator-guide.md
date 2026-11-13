---
title: "Operator guide: monitoring Datagrok"
sidebar_position: 5
description: Connect Datagrok to your monitoring stack with one OTLP endpoint, what it sends and when, the thresholds, and a reference collector, alert rules and routing.
keywords:
  - monitoring
  - OpenTelemetry
  - OTLP
  - Prometheus
  - Alertmanager
  - heartbeat
  - JSON logs
---

Datagrok detects its own [problems](problems-and-alerts.md) and pushes one log record per alert change to an
OpenTelemetry (OTLP) endpoint you run. It ships no collector, exports no metrics, and opens no port. This page
is what you need to page on it.

## The endpoint

One setting: in **Settings** > **Logger** > **Log sync**, add an **OpenTelemetry (OTLP)** destination with your
collector's OTLP/HTTP logs **Endpoint** (for example `https://otel.example.com:4318/v1/logs`) and **Auth**
`bearer`. Its **Alerts** option is on by default, so alert records and heartbeats are sent whatever **Levels**
you select. Add the `audit` and `error` levels to receive those too. All settings: [Export logs](audit.md#export-logs).

Every record carries the resource attribute `service.instance.id`, the same on every server of the deployment,
so a deployment is one series however many servers it runs.

## What arrives and when

| Record (OTLP event name) | When |
|---|---|
| `datagrok.alert.opened` | a problem starts: its condition held past the threshold below |
| `datagrok.alert.escalated` | it gets worse, for example an error incident crosses 10 times its threshold |
| `datagrok.alert.firing` | every 5 minutes while the alert is open (not stored in the database) |
| `datagrok.alert.cleared` | the condition ended, which resolves the alert |
| `datagrok.alert.acknowledged`, `datagrok.alert.resolved` | a person acknowledges or resolves it |
| `datagrok.problem.status_changed` | a person sets a problem's status (mutes it, marks it fixed or not a problem), or a timed mute ends |
| `datagrok.heartbeat` | every 5 minutes while the instance is alive (not stored) |
| `datagrok.audit.<type>` | every audit record, when the `audit` level is selected ([audit events](audit.md)) |
| `datagrok.error.<type>` | every error that has a type, when the `error` level is selected; an error without one arrives as a plain log record with no event name |
| `user-report-created` audit record and a `report` alert | a user files a problem report |

Alert records carry `datagrok.alert.id`, `.kind`, `.key`, `.name`, `.severity` (`critical`, `warning`, `info`),
`.status`, `.audience` (`platform` or `owner`) and `.url` (the evidence), and `datagrok.problem.id`. Page from
`opened` or `firing` until `resolved` with the same id; `info` is for the record only. In the database and in
other destinations the same records are the audit types `alert-opened`, `alert-escalated`, `alert-firing`,
`alert-cleared`, `alert-acknowledged`, `alert-resolved`, `problem-status-changed` and `heartbeat`.

## What Datagrok detects

Each problem is named `kind:key`, the name the [CLI and the REST API](problems-and-alerts.md#working-with-problems)
take. The defaults:

| Problem (`kind:key`) | Opens | Ends | Who acts |
|---|---|---|---|
| Service down (`health:<check>@<server>`) | 2 failed [health checks](../../develop/server-management.md#server-health) in a row on that server, for example `health:NPM@<server>` when an npm package registry does not answer | 3 passing checks in a row | platform |
| Error incident (`error-incident:<signature>`) | one error signature hits 3 users or 20 occurrences in 15 minutes, or occurs in 4 hours of the last day however rarely; critical at 10 times the users or occurrences | 60 minutes without it | platform |
| User error (`user-error:<signature>`) | one error the caller made (answered 4xx) occurs in 12 hours of the last day, or for 10 users | 6 hours without it | platform |
| Slow requests (`degraded:latency`), failing requests (`degraded:errors`, critical) | at least 20 requests in 5 minutes with p95 of 10 s or more, or 25% of them failing | 15 clean checks in a row, one a minute | platform |
| Connection down (`connection:<connection id>`) | 2 failed checks in a row; 200 connections are checked every 5 minutes, those checked longest ago first | a passing check | the connection's author |
| Container failing (`container:<image>`) | a container of the image fails to start | 5 minutes with no failing container of it | platform |
| Scheduled job failing (`job:<function id>`) | 1 failed run since the last successful one, over the last 24 hours of runs | a successful run | the function's author |
| Storage failing (`storage:<storage>`) | an S3 storage is still throttled after every retry | it answers again, or 15 minutes without a failure | platform |
| Identity provider failing (`identity-provider:<provider>`) | an OpenID provider refuses the token exchange twice within an hour | a login through it works again, or 60 minutes without a failure | platform |
| Log sync failing (`export:<destination>`) | a [Log sync](audit.md#export-logs) destination drops records, or 3 batches in a row fail | it delivers again, or 15 minutes without a failure | platform |
| User report (`report:<report id>`) | a user files a problem report | the report is resolved | platform |
| Failed logins (`rule-login-failures:<login>`) | 5 failed logins for one login in 15 minutes (the default [problem rule](problem-rules.md) `login-failures`) | `clearAfter` (5 minutes) after the condition stops holding | platform |
| Your rules (`rule-<name>:<group>`) | the rule's condition holds ([problem rules](problem-rules.md)) | `clearAfter` (5 minutes by default) after it stops holding | the rule's `owners`, unless it says `platform` |
| Rule failing (`problem-rule:<name>`) | a problem rule is invalid, fails, or exceeds a limit | it evaluates again, or is disabled or deleted | the rule's `owners` |
| Data growth (`growth:<alert>:<key>`) | a [metric alert](metric-alerts.md) holds: by default the database or the storage grew 25% in 7 days, a table over 1 GiB doubled in a day, a disk is 90% full (critical), or the garbage collector has 10 million rows pending | its alert stops holding for two collections of its metric, or is disabled or deleted | platform |
| Table not vacuumed (`vacuum:<schema.table>`) | a table of 10K rows or more has 20% dead rows and was not vacuumed for 7 days, or never; checked hourly | a vacuum brings its dead rows under 20%, or it was vacuumed within 7 days | platform |
| Metric alert failing (`problem-rule:metric-alert:<name>`) | a metric alert is invalid or holds for more than 100 keys | it evaluates again, or is disabled or deleted | platform |

An error signature is the first 12 characters of the error's stack trace hash, or, for an error without a stack
trace, of its event type id.

In **Settings** > **Alerts** an administrator can change the error incident, user error, slow and failing request
and scheduled job thresholds, the failed health checks that open a service-down problem, the number of
connections checked per run, and the problem rules, including `login-failures`. The rest is fixed: the 3 passing
checks that end a service-down problem, the vacuum thresholds, the 2 failed checks that open a connection-down problem, and the
container, storage, identity provider, Log sync and report conditions.

Silence is caught on your side: no heartbeat for 15 minutes means the instance is down, hung, or cut off.

## Reference collector

The [OpenTelemetry Collector contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
distribution. It counts alert records and heartbeats into Prometheus series; the optional `awss3` exporter
keeps a write-once copy of everything (bucket setup: [Integrity](audit.md#integrity)).

```yaml title="otel-collector.yaml"
extensions:
  bearertokenauth:
    token: ${env:DATAGROK_OTLP_TOKEN}
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        auth:
          authenticator: bearertokenauth
processors:
  resource/datagrok:
    attributes:
      - {key: datagrok_instance, from_attribute: service.instance.id, action: insert}
      - {key: datagrok_url, value: https://datagrok.example.com, action: insert}
  deltatocumulative:
    max_stale: 15m
  batch: {}
connectors:
  count:
    logs:
      datagrok_alerts:
        conditions: ['attributes["datagrok.alert.status"] != nil']
        attributes:
          - {key: datagrok.alert.id}
          - {key: datagrok.alert.kind}
          - {key: datagrok.alert.key, default_value: ""}
          - {key: datagrok.alert.name}
          - {key: datagrok.alert.status}
          - {key: datagrok.alert.severity, default_value: warning}
          - {key: datagrok.alert.audience, default_value: platform}
          - {key: datagrok.alert.url, default_value: ""}
      datagrok_heartbeats:
        conditions: ['attributes["datagrok.audit_type"] == "heartbeat"']
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
    resource_to_telemetry_conversion: {enabled: true}
    metric_expiration: 15m
  prometheus/push:
    endpoint: 0.0.0.0:8890
    resource_to_telemetry_conversion: {enabled: true}
    metric_expiration: 3m
    send_timestamps: false
  awss3:
    s3uploader: {region: us-east-1, s3_bucket: datagrok-audit-worm, s3_prefix: datagrok, compression: gzip}
    marshaler: otlp_json
service:
  extensions: [bearertokenauth]
  pipelines:
    logs:
      receivers: [otlp]
      processors: [resource/datagrok, batch]
      exporters: [count, awss3]
    metrics:
      receivers: [count]
      processors: [deltatocumulative, batch]
      exporters: [prometheus]
    metrics/push:
      receivers: [otlp]
      processors: [resource/datagrok, batch]
      exporters: [prometheus/push]
```

Prometheus scrapes `:8889` and sees `datagrok_alerts_total` and `datagrok_heartbeats_total`. Drop `awss3` from the
exporters if you don't keep a WORM copy. On another backend (Grafana Cloud, Datadog, Elastic), skip the counting:
open an incident on `datagrok.alert.opened` and close it on `datagrok.alert.resolved` with the same
`datagrok.alert.id`.

### Server metrics

When the endpoint is ticked in the **Metrics** group, Datagrok also pushes the state of its servers, database and
storage every minute to `/v1/metrics` of the same endpoint. The `metrics/push` pipeline exports these as they are on
`:8890`; a series of a server that stops pushing goes after `metric_expiration` (3 missed snapshots). Each series
carries `datagrok_instance` and `datagrok_url`; per-server series also carry `datagrok_server`.

| Series | Labels | Value |
|---|---|---|
| `datagrok_server_info` | `datagrok_version` | 1 per running server |
| `datagrok_server_isolates`, `datagrok_server_sockets`, `datagrok_server_open_files_limit` | | per server |
| `datagrok_server_http_connections`, `datagrok_server_db_connections` | | connections of the server process |
| `datagrok_server_service_up` | `datagrok_service`, `datagrok_type` | 1 running, 0 failed or blocked |
| `datagrok_isolate_http_requests_in_flight`, `datagrok_isolate_http_requests_5m` | `datagrok_isolate` | per isolate |
| `datagrok_isolate_db_pool_connections`, `_in_use`, `_waiting`, `_max` | `datagrok_isolate` | database pool of the isolate |
| `datagrok_disk_used_bytes`, `datagrok_disk_free_bytes`, `datagrok_disk_usage_percent` | `datagrok_device`, `datagrok_mount` | per server |
| `datagrok_db_size_bytes`, `datagrok_db_connections_max`, `datagrok_db_lock_waits` | | database |
| `datagrok_db_connections` | `datagrok_state` (`active`, `idle`, `idle_in_transaction`) | database |
| `datagrok_db_oldest_idle_transaction_seconds`, `datagrok_db_cache_hit_percent` | | database |
| `datagrok_queue_calls` | `datagrok_status` (`queued`, `running`, `stale`) | function calls |
| `datagrok_http_requests_5m`, `datagrok_http_errors_5m`, `datagrok_http_latency_p95_5m_milliseconds`, `datagrok_sessions_active_5m` | | last 5 minutes |
| `datagrok_alerts_open` | `datagrok_severity` | open alerts |
| `datagrok_db_table_size_bytes`, `datagrok_db_table_rows` | `datagrok_table` | the 20 largest tables |
| `datagrok_db_dead_tables`, `datagrok_db_max_dead_percent` | | dead rows |
| `datagrok_storage_size_bytes`, `datagrok_storage_objects` | `datagrok_location`, `datagrok_nature` | file storage |
| `datagrok_gc_pending` | `datagrok_key` | rows waiting for cleanup |

Example rules:

```yaml
- alert: DatagrokDbPoolWaiting
  expr: datagrok_isolate_db_pool_waiting > 0
  for: 5m
  labels: {severity: warning, audience: platform}
  annotations:
    summary: '{{ $labels.datagrok_instance }}: requests wait for a database connection on {{ $labels.datagrok_server }} isolate {{ $labels.datagrok_isolate }}'
- alert: DatagrokDbConnectionsHigh
  expr: |-
    datagrok_db_connections{datagrok_state="active"}
      / on (datagrok_instance) group_left datagrok_db_connections_max > 0.8
  for: 5m
  labels: {severity: warning, audience: platform}
  annotations:
    summary: '{{ $labels.datagrok_instance }}: over 80% of database connections are active'
```

## Reference alert rules

A counter is born by its first record, so every rule also matches a series that is new in the window
(`x unless x offset W`).

```yaml title="datagrok-rules.yaml"
groups:
- name: datagrok
  rules:
  - alert: DatagrokProblem
    expr: |-
      max by (datagrok_instance, datagrok_url, datagrok_alert_id, datagrok_alert_kind, datagrok_alert_key, datagrok_alert_name, datagrok_alert_severity, datagrok_alert_audience, datagrok_alert_url) (
        (increase(datagrok_alerts_total{datagrok_alert_status=~"opened|escalated|firing",datagrok_alert_severity!="info"}[12m]) > 0)
        or (datagrok_alerts_total{datagrok_alert_status=~"opened|escalated|firing",datagrok_alert_severity!="info"}
            unless datagrok_alerts_total{datagrok_alert_status=~"opened|escalated|firing",datagrok_alert_severity!="info"} offset 12m)
      )
      unless on (datagrok_instance, datagrok_alert_id) (
        (increase(datagrok_alerts_total{datagrok_alert_status="resolved"}[12m]) > 0)
        or (datagrok_alerts_total{datagrok_alert_status="resolved"} unless datagrok_alerts_total{datagrok_alert_status="resolved"} offset 12m)
      )
    labels:
      severity: '{{ $labels.datagrok_alert_severity }}'
      audience: '{{ $labels.datagrok_alert_audience }}'
    annotations:
      summary: '{{ $labels.datagrok_instance }}: {{ $labels.datagrok_alert_name }} ({{ $labels.datagrok_alert_kind }}{{ if $labels.datagrok_alert_key }} {{ $labels.datagrok_alert_key }}{{ end }})'
      url: '{{ if $labels.datagrok_alert_url }}{{ $labels.datagrok_alert_url }}{{ else }}{{ $labels.datagrok_url }}{{ end }}'
  - alert: DatagrokHeartbeatMissing
    expr: |-
      max by (datagrok_instance, datagrok_url) (max_over_time(datagrok_heartbeats_total[24h]))
      unless max by (datagrok_instance, datagrok_url) (
        (increase(datagrok_heartbeats_total[15m]) > 0)
        or (datagrok_heartbeats_total unless datagrok_heartbeats_total offset 15m)
      )
    for: 5m
    labels:
      severity: critical
      audience: platform
    annotations:
      summary: '{{ $labels.datagrok_instance }}: no heartbeat for 15 minutes'
      url: '{{ $labels.datagrok_url }}'
```

## Routing

Severity decides how loud, audience decides who. `owner` alerts (a data source down, a failing scheduled job, a
rule with `owners`) already reach their owner in Datagrok; send them to a channel, not to the on-call.

```yaml title="alertmanager.yaml"
route:
  receiver: platform-chat
  group_by: [alertname, datagrok_instance, datagrok_alert_id]
  routes:
  - matchers: ['audience="owner"']
    receiver: owners-chat
  - matchers: ['severity="critical"']
    receiver: platform-pager
inhibit_rules:
- source_matchers: ['severity="critical"']
  target_matchers: ['severity="warning"']
  equal: [alertname, datagrok_instance, datagrok_alert_id]
receivers:
- name: platform-chat
- name: platform-pager
- name: owners-chat
```

## Logs of the other services

Datlas alone pushes. The other services write one JSON line per record to stdout for your cluster's log
collection, with the keys datlas prints (`time`, `level`, `service`, `message`, `params`, `stackTrace`, and
`sessionId` when known), secrets removed. Turn it on with `jsonLogs: true` in `GROK_PARAMETERS` for the server,
and the environment variable `GROK_JSON_LOGS=true` for the spawner and Celery workers; the grok_pipe proxy
always writes JSON. Check it with `kubectl logs deploy/<release>-spawner --tail=3`.
