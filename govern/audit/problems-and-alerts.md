---
title: "Problems and alerts"
sidebar_position: 3
description: How Datagrok detects problems, keeps them, and alerts your monitoring system once per problem until someone resolves the alert.
keywords:
  - alerts
  - problems
  - monitoring
  - mute alert
  - heartbeat
  - OpenTelemetry
---

Datagrok watches itself. When a service fails, one error hits many users, requests slow down,
an account keeps failing to sign in, a data source stops answering, or a user reports a problem,
the server records a **problem** and raises an **alert** about it. The alert goes to your
monitoring system as a log record, once, and stays open until the problem ends or a person resolves it.

| | Problem | Alert |
|---|---|---|
| What it is | what is wrong, for example "service Jupyter fails" | the notification that it went wrong |
| How long it lives | one per condition; forgotten 30 days after it ended with no open alert, unless it is muted or not a problem | until the problem ends or a person resolves it |
| Who changes it | you set its status; Datagrok tracks whether it is happening | Datagrok opens it; you acknowledge and resolve it |

## What Datagrok detects

Services that fail their health checks, errors that hit many users or keep recurring, errors users keep making,
slow or failing requests, data connections and scheduled jobs that fail, containers that don't start, storage,
identity providers and Log sync destinations that keep failing, problem reports, the database, storage or disks
growing too much ([metric alerts](metric-alerts.md)), tables that no vacuum reached for long (`vacuum`: 10K rows or
more, 20% of them dead, not vacuumed for 7 days), and the conditions of your own
[problem rules](problem-rules.md), such as the default `login-failures`. When each one opens and ends, who acts
on it, and which thresholds an administrator can change in **Health** > **Alerts** > **Rules**:
[What Datagrok detects](operator-guide.md#what-datagrok-detects) in the operator guide.

## Statuses

Each problem has a status that decides whether it alerts:

| Status | Meaning | When it happens again |
|---|---|---|
| **Active** | needs attention | alerts |
| **Muted** | known, quiet for now: for a while, until a version, or until you lift the mute | no alert; active again when the mute ends |
| **Not a problem** | expected behavior | never alerts. An error marked so stops counting as an error |
| **Fixed** | someone fixed it | alerts again only if it comes back after the fix, marked as a regression |

What to do with an alert:

* **Resolve** it when you have seen it. The problem stays active: if the condition still holds, a new alert opens on the next check.
* **Mute** the problem to stop its alerts. Muting resolves the open alert, and is the way to stop alerts about a problem.
* Mark the problem **fixed** to hear about it only if it comes back.
* Each action has its undo: **Unacknowledge**, **Reopen** a resolved alert, **Unmute**, **Undo not a problem**, **Undo fixed**.

An alert that is open does not page again while its condition persists. When the condition ends, the
alert is cleared and resolved.

## The Health overview

**Browse** > **Platform** > **Health** shows the state of the instance on one page:

* **Status**: "All clear", or how many problems need attention, by severity. A problem needs attention
  while its condition holds and nobody muted or dismissed it.
* **Vitals** of the last 24 hours against the day before: requests and the share answered with an error status
  (400 or above), p95 latency, errors and the users who met them, the function queue, the database size and cache
  hit rate, and blocked database connections; and the HTTP connections and open sockets of all server instances,
  with the busiest one's share of its open files limit. A tile opens **Metrics**; **Errors** opens the error events
  in **Logs**; **HTTP connections** and **Open sockets** open a table of each instance and isolate. Growing sockets
  raise the [metric alerts](metric-alerts.md) `socket-growth` and `too-many-sockets`.
* **Needs attention**: the most severe and latest problems. Click one to see it in the context panel; hover
  it to acknowledge or resolve its alert, mute it, or open its evidence.
* **Top errors** of the last 24 hours. Click one to see its events in **Logs**.
* **Services**: every health check, the failing ones first. Click a service to open its logs.
* **Monitoring setup**: the alert rules, the log settings, and how long records are kept.

The page refreshes every minute.

Every Health page works the same way:

* It appears at once as a skeleton; each card and block then loads on its own and refreshes in place.
* The ribbon shows when the page was last updated; the refresh icon spins while it loads.
* Hover a card, a column header or a field to read what it is, which values are good and which are a concern.
* Click a card to drill down to what is behind the number.
* **Export as dashboard** (the archive icon) saves every table of the page as a zip. Drop the file into Datagrok
  to open it as a dashboard, for example to send the state of an instance to support.

## Alert rules

**Health** > **Alerts** > **Rules** holds everything that raises a problem:

* **Built-in detectors**: error incidents, user errors, degraded requests, connections, service health,
  scheduled jobs, dashboards and data growth. Each card has the detector's thresholds and says how many of its
  problems are failing now.
* **Custom rules**: your own conditions on logged events.

One **Save** saves both.

## Metrics, logs and log settings

* **Metrics**: the database, connections, the function queue, storage and disks, errors, latency and sessions
  for the chosen window; data growth; the slowest queries; the largest and the least healthy tables; and the
  HTTP routes. Click a failed share of a route to see the failed requests and their log.
* **Logs**: one explorer for the platform's events and the logs of its services. Service logs are read from
  what the services pushed into Datagrok; switch to **Live** to follow a container as it writes. On AWS
  deployments the explorer also reads CloudWatch and the log archive.
* **Log settings**: the log groups, where records are sent, and the in-memory buffer.

## The Alerts view

**Browse** > **Platform** > **Health** > **Alerts** lists the active problems: those whose condition holds
or whose alert is not resolved yet, the failing and most severe first. Set **Show** to **All** to see the
problems that cleared as well. A problem's row reads:

| Column | What it shows | Values |
|---|---|---|
| **Severity** | how bad it is | critical, warning, info |
| **Condition** | whether it is happening now, as Datagrok sees it | failing (red), ok (green) |
| **Alert** | its alert | open (red), acknowledged (orange), resolved (green) |
| **Handling** | the status you set | watched (blue): an active problem, guarded and alerting when it fails; muted, not a problem (grey); fixed (green) |

The icons in **Actions** acknowledge or resolve the alert, mute the problem, and open its evidence. The
**Actions** section of a problem's context panel also marks it fixed or not a problem, or watches it again.
The **Diagnose** section links to where to look next: the rule or the detector that raised the problem, the
logs of its service, the errors of the last day, or the request and database metrics. Hover a column header
to read what the column means.

## Where alerts go

Alerts are log records, all of one alert with the same alert id, plus a heartbeat every 5 minutes while the
instance is alive ([the records and when they arrive](operator-guide.md#what-arrives-and-when)). Send them to your
monitoring system with an OpenTelemetry destination in [Log sync](audit.md#export-logs) (its **Alerts** option is
on by default) and page from them:

| Your stack | Rule |
|---|---|
| Prometheus and Alertmanager behind an OpenTelemetry Collector | count the records by alert id; fire from `opened` or `firing` until `resolved` |
| Grafana Cloud, Datadog, New Relic, Elastic, Dynatrace | open on `datagrok.alert.opened`, close on `datagrok.alert.resolved` with the same `datagrok.alert.id` |
| A log store or SIEM | alert on the `alert-opened` record |

Page on a missing heartbeat too: no heartbeat for 15 minutes means the instance is down, hung, or cut off.
A reference collector, alert rules and routing are in the [operator guide](operator-guide.md).

Datagrok also notifies people in the product when an alert opens or gets worse, once per alert:

* An owner's alert goes to the owner: the author of the connection or of the scheduled function, or the
  `owners` of a [problem rule](problem-rules.md). It links to the connection or function.
* A platform alert, and an owner's alert with no owner, goes to everyone with the **Manage Alerts** permission.

Turn these notifications off in your notification settings. A query on a connection that
was down on its last check says so in its **Details**, and warns before it runs. A scheduled function shows
its last successful and last failed run in its **Details**.
Each record carries the problem's audience: `platform` for the platform's operators, `owner` for problems
that belong to the owner of a data connection or a rule, so the people who run the platform are not paged for them.

## Working with problems

Problems and alerts need the **Manage Alerts** [global permission](../access-control/access-control.md#global-permissions),
which administrators have. Use the [`grok` CLI](https://github.com/datagrok-ai/public/blob/master/tools/GROK_S.md)
or the REST API (`/api/problems`). A problem is named by its id or by `kind:key`, for example
`health:Jupyter@<server>`, `report:<report id>` or `connection:<connection id>`:

```bash
grok s observe problems list --alert-status open           # the open alerts
grok s observe problems resolve report:<report id> --reason "duplicate"
grok s observe problems list --status active --since 7d
grok s observe problems status connection:<connection id> --data '{"status": "muted", "reason": "monthly maintenance", "until": "2026-10-04T06:00:00Z"}'
grok s observe problems status health:Jupyter@<server> --data '{"status": "fixed", "reason": "kernel image rebuilt"}'
grok s observe problems history health:Jupyter@<server>    # everything that happened to it
```

An error incident's **Diagnose** links open the errors of the last day and the platform events in
**Health** > **Logs**; **Top errors** on the overview opens each error's events there.
