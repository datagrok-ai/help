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
| `datagrok.alert.cleared` | the condition ended; the alert stays open until a person resolves it |
| `datagrok.alert.acknowledged`, `datagrok.alert.resolved` | a person acknowledges or resolves it |
| `datagrok.heartbeat` | every 5 minutes while the instance is alive (not stored) |
| `datagrok.audit.<type>` | every audit record, when the `audit` level is selected ([audit events](audit.md)) |
| `datagrok.error.<type>` | every error, when the `error` level is selected |
| `user-report-created` audit record and a `report` alert | a user files a problem report |

Alert records carry `datagrok.alert.id`, `.kind`, `.key`, `.name`, `.severity` (`critical`, `warning`, `info`),
`.status`, `.audience` (`platform` or `owner`) and `.url` (the evidence). Page from `opened` or `firing` until
`resolved` with the same id; `info` is for the record only.

## Thresholds

The defaults, all editable in **Settings** > **Alerts**:

| Problem | Opens | Ends |
|---|---|---|
| Service down | 2 failed health checks in a row | a passing check |
| Error incident | one error signature hits 3 users or 20 occurrences in 15 minutes, or occurs in 4 hours of the last day; critical at 10 times that | 60 minutes without it |
| User error | one 4xx error in 12 hours of the last day, or for 10 users | 6 hours without it |
| Slow or failing requests | at least 20 requests in 5 minutes with p95 of 10 s or more, or 25% failing | 5 clean checks in a row |
| Connection down | 2 failed checks in a row (200 connections checked every 5 minutes) | a passing check |
| Scheduled job failing | 1 failed run, over the last 24 hours of runs | a successful run |
| Failed logins | 5 for one login in 15 minutes (problem rule `login`) | the window passes |

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
```

Prometheus scrapes `:8889` and sees `datagrok_alerts_total` and `datagrok_heartbeats_total`. Drop `awss3` from the
exporters if you don't keep a WORM copy. On another backend (Grafana Cloud, Datadog, Elastic), skip the counting:
open an incident on `datagrok.alert.opened` and close it on `datagrok.alert.resolved` with the same
`datagrok.alert.id`.

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
