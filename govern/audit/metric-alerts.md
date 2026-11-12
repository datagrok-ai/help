---
title: "Metric alerts"
sidebar_position: 4.5
description: Alert when the platform's database, storage or disks grow too much, the garbage collector falls behind, or a server leaks sockets.
keywords:
  - metric alerts
  - data growth
  - storage growth
  - database size
  - disk full
  - open sockets
  - metricAlerts
---

Datagrok keeps track of how its own data grows: the size and rows of each table of its database (and the
counts of categories such as events by source or entities by type), its file storage by kind of data and
location, each server's disk and open sockets, and what the garbage collector deleted and still has to delete. A **metric alert**
watches these numbers and raises a [problem](problems-and-alerts.md) when one is too high or grows too fast,
with the same statuses, alerts and notifications as every other problem.

You can see the numbers in **Browse** > **Platform** > **Observability** > **Metrics**: the data growth cards and the **Data growth**
panel, with each value's change over 1, 7 and 30 days and its daily trend. Seeing them needs the
**View Telemetry** [global permission](../access-control/access-control.md#global-permissions).

## What is measured

| Metric | Key | Measured |
|---|---|---|
| `db.bytes` | a table (`events`), or `(total)` for the whole database | hourly |
| `db.rows` | a table | hourly, an estimate |
| `db.count` | a category of a table: `events/source=usage`, `entities/type=Project`, `func_calls/status=Failed`, … | daily; estimated on tables over 5 million rows |
| `storage.bytes`, `storage.objects` | `shared`, `shared/<kind>` (`packages`, `app-data`, `tables`, `user-files`, …), `shared/packages/<package>`; `local@<server>` for a server's own disk | every 6 hours |
| `disk.used_bytes`, `disk.free_bytes`, `disk.used_pct` | `local@<server>` | hourly |
| `gc.deleted` | what the garbage collector shrank: `events/source=debug`, `test_runs`, `shared/packages`, … | after each collection |
| `gc.pending` | the same keys, for the steps that can be counted | daily, and after each collection |
| `server.sockets`, `server.http_connections`, `server.db_connections` | `local@<server>`: the sockets the server process holds, the HTTP connections it accepted, its connections to the platform database | every 5 minutes |

The schedule and the categories counted are settings in **Settings** > **Alerts** > **Data growth**:
`metricsEveryMinutes` (60), `metricsBreakdownHours` (24), `metricsStorageHours` (6) and `metricsBreakdowns`.
The samples are kept for 400 days, the hourly ones for 14 (`metricSamplesRetention` in the garbage collector
settings).

## Where alerts live

The alerts are one setting, **Metric alerts** (`metricAlerts`), in **Settings** > **Alerts** > **Data growth**:
a JSON array, at most 30 alerts. Saving checks every alert and refuses the save with the first error. Changing it
needs the **Edit Plugins Settings** global permission.

Out of the box it holds:

| Alert | Metric, key | Raises when | Severity |
|---|---|---|---|
| `database-growth` | `db.bytes`, `(total)` | the database grew 25% in 7 days | warning |
| `table-growth` | `db.bytes`, any table | a table is over 1 GiB **and** doubled in a day | warning |
| `storage-growth` | `storage.bytes`, `shared` | the storage grew 25% in 7 days | warning |
| `disk-full` | `disk.used_pct`, any server | a disk is over 90% full | critical |
| `gc-backlog` | `gc.pending`, any key | the garbage collector has over 10 million rows to delete | warning |
| `socket-growth` | `server.sockets`, any server | a server holds over 1,000 sockets **and** twice as many as a day before: a leak | warning |
| `too-many-sockets` | `server.sockets`, any server | a server holds over 10,000 sockets | critical |

Growth needs history: no growth alert holds until there is a sample old enough to compare with, so a new
installation stays quiet for the first week. Saving your own alerts replaces the defaults, so keep the ones you
want in the array.

## An alert

```json
{
  "name": "table-growth",
  "metric": "db.bytes",
  "key": "*",
  "above": 1073741824,
  "growth": {"percent": 100, "days": 1},
  "severity": "warning",
  "summary": "{key} {metric} {value} ({growth} in {days} d)"
}
```

| Field | Default | Description |
|---|---|---|
| `name` | required | 2–27 lowercase letters, digits or dashes, starting with a letter; unique. Its problems are of kind `growth`, keyed `<name>:<key>`, and its alert name is `Datagrok` and the name in Pascal case (`table-growth`: `DatagrokTableGrowth`) |
| `enabled` | `true` | |
| `metric` | required | one of the metrics above |
| `key` | required | a key, or a pattern: `*` stands for any characters, `?` for one (`events/source=*`, `local@*`) |
| `above` | none | holds when the latest value is greater |
| `growth` | none | `{"percent": 25, "days": 7}` or `{"by": 1000000, "days": 1}`: holds when the latest value grew by that much since the sample `days` (1–90) earlier |
| `severity` | `warning` | `info` records the problem and never alerts; `warning`; `critical` |
| `summary` | generated | the alert text, with placeholders `{alert}`, `{metric}`, `{key}`, `{value}`, `{previous}`, `{growth}`, `{percent}`, `{days}`, `{above}`. Sizes read like `12.3 GB` |

Give `above`, `growth` or both; with both, both must hold, so a size floor keeps small tables from alerting on
a doubling.

A problem ends when its alert no longer holds for two collections of its metric (two hours for the hourly
ones, ten minutes for the sockets), so a value hovering at the threshold is one problem, not many. Removing or disabling an alert ends its
problems. Alerts go to everyone with the **Manage Alerts** permission.

An alert that cannot be evaluated, or that holds for more than 100 keys at once, raises a `problem-rule`
problem keyed `metric-alert:<name>`; the other alerts still run.

## Examples

Error events grow by a million a day:

```json
{"name": "error-flood", "metric": "db.count", "key": "events/source=error", "growth": {"by": 1000000, "days": 1}}
```

Any package's files in the storage pass 5 GB:

```json
{"name": "big-package", "metric": "storage.bytes", "key": "shared/packages/*", "above": 5368709120}
```

Debug events waiting for the garbage collector grow by half in a week (it is off, or falls behind):

```json
{"name": "gc-behind", "metric": "gc.pending", "key": "events/source=debug", "growth": {"percent": 50, "days": 7}}
```

HTTP connections to one server pass 2,000:

```json
{"name": "http-flood", "metric": "server.http_connections", "key": "*", "above": 2000}
```

## From the API

`grok.dapi.admin.getGrowthMetrics({area, days})` returns the same numbers as the Metrics page: one row per key
with its value now, its change over 1, 7 and 30 days, its daily trend, what the garbage collector did to it, and
the metric alerts that cover it. It needs **View Telemetry**; the ids of the alerts' problems also need **Manage
Alerts**.

The sockets of every server instance and of each of its isolates, the threads that serve requests, are gathered
when you ask for them:

* `GET /api/admin/connections` (**View Telemetry**): one entry per instance with its process's `openSockets`,
  `httpConnections`, `dbConnections` and `openFilesLimit`, and `isolates`: for each, the HTTP connections it
  accepted (`httpActive`, `httpIdle`) and its database pool connections (`dbInUse`, `dbAvailable`, `dbWaiting`).
* `GET /api/admin/metrics` has them under `instances`, and their sum under `process`, with `usedPct`, the busiest
  instance's share of its open files limit.
* `GET /api/admin/health?instances=true` (**View Telemetry**) describes them all in the record `sockets`, such as
  `3 instances, 9 isolates: 210 open sockets, 7 HTTP connections, 165 to the database; ...`, then each instance.
  Without `instances`, as the Kubernetes probes call it, the record covers only the server that answered.

**Observability** > **Metrics** > **Servers**, and the overview's **HTTP connections** and **Open sockets**, open
them as a table, a row per instance and per isolate. The sockets are read from `/proc`, so a server not on Linux
has none.
