---
title: "Problem rules"
sidebar_position: 4
description: Define your own problem types as conditions over the Datagrok log, test them, and get alerts like the built-in ones.
keywords:
  - problem rules
  - custom alerts
  - alert rules
  - log conditions
  - problemRules
---

A **problem rule** is your own kind of [problem](problems-and-alerts.md): a condition over the
platform's log, such as "one account fails to sign in five times in 15 minutes" or "no connection
check for 30 minutes". Every group of events the condition holds for becomes a problem, with the same
statuses and alerts as the built-in ones: it alerts once, stays open until resolved, and can be
muted, dismissed or marked fixed.

A rule reads the events Datagrok saves: errors, audit and usage records (see [Audit](audit.md)).
A level, such as debug, is matched only when the logger saves that level.

## Where rules live

The rules are one setting, **Problem rules**, on **Settings** > **Alerts**: a JSON array of rules.
Saving checks every rule and refuses the save with the first error. Changing it needs the
**Edit Plugins Settings** [global permission](../access-control/access-control.md#global-permissions)
and is recorded as a `settings-changed` audit event.

Out of the box the array holds one rule, `login`: 5 failed sign-ins of one login within 15 minutes.
Saving your own rules replaces it, so keep it in the array if you want it.

| Where | |
|---|---|
| **Settings** > **Alerts** | edit **Problem rules**, then **Test rules** |
| `grok s observe rules` | `get`, `put --json rules.json`, `test` ([grok CLI](https://github.com/datagrok-ai/public/blob/master/tools/GROK_S.md)) |
| `GROK_PARAMETERS` | `settings.alerts.problemRules`, applied at every start ([below](#rules-the-deployment-defines)) |

## A rule

```json
{
  "name": "failed-logins-per-user",
  "description": "One account failing to sign in again and again",
  "severity": "warning",
  "match": {"source": "audit", "type": "user-login-failed"},
  "groupBy": "param:login",
  "window": 15,
  "when": {"count": 5},
  "summary": "{count} failed logins for {group} in {window} min"
}
```

| Field | Default | Description |
|---|---|---|
| `name` | required | 2–27 lowercase letters, digits or dashes, starting with a letter; unique. Its problems are of kind `rule-<name>` |
| `description` | | Free text |
| `enabled` | `true` | |
| `severity` | `warning` | `info` records the problem and never alerts; `warning`; `critical` |
| `audience` | `owner` | `owner`, or `platform` to page the platform's operators |
| `owners` | none | up to 10 logins or group names notified in the product when an `owner` alert opens; none: everyone with **Manage Alerts** |
| `alertname` | `DatagrokRule` | The alert name your monitoring system sees |
| `match` | required | Which events count, below |
| `groupBy` | none | One or two of `user`, `session`, `type`, `signature`, `param:<name>`. Each group is its own problem |
| `window` | 60 | Minutes the condition looks back, 1–1440 |
| `every` | 1 | Minutes between evaluations, 1–60 |
| `clearAfter` | 5 | Minutes the condition must stop holding before the problem clears, 0–1440 |
| `when` | `{"count": 1}` | Conditions, all of which must hold, below |
| `summary` | generated | The alert text, with placeholders, below |

### Match

| Field | Matches |
|---|---|
| `source` | `error`, `warning`, `info`, `debug`, `audit`, `usage`, or a list. Without it, `type` matches audit and usage events |
| `type` | the event type, such as `user-login-failed` or `connection-checked` (for errors: the error message); one or a list of up to 20 |
| `text` | keywords that must all occur in the message, ignoring case; up to 10 |
| `regex` | a regular expression over the message, ignoring case |
| `stackHash` | errors whose stack trace hash starts with these 6–32 hex characters |
| `params` | up to 10 conditions on event parameters: `{"name": "packageName", "op": "=", "value": "Chem"}`. Operators `=`, `!=`, `contains`, `in` (a list), `>`, `>=`, `<`, `<=`, `exists`, `missing` |
| `users`, `groups` | only events of these users (logins), or of members of these groups |

### Conditions

| Condition | Holds when, per group | Example |
|---|---|---|
| `count` | at least N matching events in the window | `{"count": 5}` |
| `users` | at least N distinct users among them | `{"users": 5}` |
| `value` | an aggregate (`avg`, `min`, `max`, `sum`, `p95`) of a numeric parameter compares to a threshold | `{"value": {"param": "ms", "agg": "avg", "op": ">=", "threshold": 5000}}` |
| `absent` | no matching event for `for` minutes; with `groupBy`, a group seen within `lookback` minutes (1440) has gone silent. Stands alone | `{"absent": {"for": 30}}` |

A problem clears when its condition has not held for `clearAfter` minutes. An `absent` problem clears
when a matching event arrives. Disabling or removing a rule clears its problems.

### Summary

`summary` may use `{rule}`, `{group}`, `{count}`, `{users}`, `{value}`, `{window}`, `{for}`,
`{lookback}`, `{first}`, `{last}` and `{message}` (the newest matching event's message). Without a
summary, Datagrok writes one from the condition.

## Test

**Test rules** on **Settings** > **Alerts**, or `grok s observe rules test`, evaluates the saved
rules once, now, without raising anything: for each rule, how many events it matched in its window
and the groups it holds for. It needs the **Manage Alerts** and **View Telemetry** permissions.

## Examples

| Rule | What it catches |
|---|---|
| `failed-logins-per-user` | one account failing to sign in again and again |
| `query-timeouts` | a connection whose queries keep timing out |
| `chem-error-many-users` | one Chem error hitting five users within 15 minutes |
| `slow-connection-checks` | a data connection answering slowly on average |
| `partner-bulk-downloads` | a member of the External partners group opening many files (the group must exist) |
| `connection-monitor-silent` | the connection checks have stopped; it pages the platform |

```json
[
  {"name": "failed-logins-per-user", "severity": "warning",
   "match": {"source": "audit", "type": "user-login-failed"},
   "groupBy": "param:login", "window": 15, "when": {"count": 5},
   "summary": "{count} failed logins for {group} in {window} min"},

  {"name": "query-timeouts", "severity": "warning",
   "match": {"source": "error", "text": ["timeout"], "params": [{"name": "connection", "op": "exists"}]},
   "groupBy": "param:connection", "window": 60, "when": {"count": 10},
   "summary": "{count} query timeouts on {group} in the last hour"},

  {"name": "chem-error-many-users", "severity": "critical",
   "match": {"source": "error", "params": [{"name": "packageName", "op": "=", "value": "Chem"}]},
   "groupBy": "signature", "window": 15, "when": {"users": 5},
   "summary": "{users} users hit the same Chem error in {window} min: {message}"},

  {"name": "slow-connection-checks", "severity": "warning",
   "match": {"source": "audit", "type": "connection-checked", "params": [{"name": "status", "op": "=", "value": "ok"}]},
   "groupBy": "param:connection", "window": 60,
   "when": {"count": 3, "value": {"param": "ms", "agg": "avg", "op": ">=", "threshold": 5000}},
   "summary": "{group} answers in {value} ms on average"},

  {"name": "partner-bulk-downloads", "severity": "warning",
   "match": {"source": "usage", "type": "file-open", "groups": ["External partners"]},
   "groupBy": "user", "window": 60, "when": {"count": 200},
   "summary": "{group} opened {count} files in an hour"},

  {"name": "connection-monitor-silent", "severity": "critical", "audience": "platform",
   "match": {"source": "audit", "type": "connection-checked"},
   "when": {"absent": {"for": 30}},
   "summary": "No connection check for {for} min: the connection monitor is not running"}
]
```

## Limits

| Limit | Value |
|---|---|
| Rules | 50 |
| Problems raised per rule at a time | 100; beyond that, a `problem-rule` problem says so |
| One evaluation | 10 seconds per query |
| Sizes | 10 parameters, 10 keywords, 20 types, 50 users, 10 groups, 50 `in` values |

A rule that fails or exceeds a limit raises a `problem-rule` problem for its owners until it
evaluates again.

## Rules the deployment defines

Set the rules in [`GROK_PARAMETERS`](../../deploy/configuration.md#settings) under
`settings.alerts.problemRules`, as the JSON array written as a string. They are written to the
settings at every start, replacing what was saved in **Settings** since.

```json
{
  "settings": {
    "alerts": {
      "problemRules": "[{\"name\": \"connection-monitor-silent\", \"severity\": \"critical\", \"audience\": \"platform\", \"match\": {\"source\": \"audit\", \"type\": \"connection-checked\"}, \"when\": {\"absent\": {\"for\": 30}}}]"
    }
  }
}
```

## What leaves the instance

A rule's alerts are the same records as any alert (see [where alerts go](problems-and-alerts.md#where-alerts-go)):
they carry the rule's kind (`rule-<name>`), the group as the alert key, the severity, the audience and the summary.
Keep personal data out of `groupBy` and `summary` if your monitoring system should not see it.
