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
identity providers and Log sync destinations that keep failing, problem reports, and the conditions of your own
[problem rules](problem-rules.md), such as the default `login-failures`. When each one opens and ends, who acts
on it, and which thresholds an administrator can change in **Settings** > **Alerts**:
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

An alert that is open does not page again while its condition persists. When the condition ends, the
alert is cleared and resolved.

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

In [Usage Analysis](usage-analysis.md), the **Errors** tab shows the error incident of each error.
