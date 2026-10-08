---
title: "Problem rules"
sidebar_position: 4
description: Define your own problem types as conditions over the Datagrok log, test them against past events, and get alerts like the built-in ones.
keywords:
  - problem rules
  - custom alerts
  - alert rules
  - log conditions
  - GROK_PARAMETERS problemRules
---

A **problem rule** is your own kind of [problem](problems-and-alerts.md): a condition over the
platform's log, such as "one account fails to sign in five times in 15 minutes" or "no connection
check for 30 minutes". Every group of events the condition holds for becomes a problem, with the same
statuses and alerts as the built-in ones: it alerts once, stays open until resolved, and can be
muted, dismissed or marked fixed.

A rule reads the events Datagrok saves: errors, audit and usage records (see [Audit](audit.md)).
A level, such as debug, is matched only when the logger saves that level.

## Where to create rules

| Where | |
|---|---|
| **Settings** > **Problem rules** | the list of rules; select one to edit it as JSON, **Test** it, **Save**, enable, disable or delete it. **New…** starts from a template for the condition you pick. Below the rule are its current problems |
| `grok s observe rules` | `list`, `get`, `add`, `edit`, `enable`, `disable`, `delete`, `test` ([grok CLI](https://github.com/datagrok-ai/public/blob/master/tools/GROK_S.md)) |
| `GROK_PARAMETERS` `problemRules` | rules the deployment defines; read-only everywhere else |

Rules need the **ManageAlerts** [global permission](../access-control/access-control.md#global-permissions).
Every change is recorded as a `problem-rule-changed` audit event.

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
| `name` | required | 2–27 lowercase letters, digits or dashes, starting with a letter. Its problems are of kind `rule-<name>` |
| `description` | | Free text |
| `enabled` | `true` | |
| `severity` | `warning` | `info` records the problem and never alerts; `warning`; `critical` |
| `audience` | `owner` | `platform` (pages the platform's operators) is allowed only in `GROK_PARAMETERS` |
| `alertname` | `DatagrokRule` | The alert name your monitoring system sees |
| `match` | required | Which events count, below |
| `groupBy` | none | One or two of `user`, `session`, `server`, `request`, `type`, `signature`, `param:<name>`. Each group is its own problem |
| `window` | 60 | Minutes the condition looks back, 1–1440 (360 for `spike`) |
| `every` | 1 | Minutes between evaluations, 1–60 (10 for `new` and `spike`) |
| `clearAfter` | 5 | Minutes the condition must stop holding before the problem clears, 0–1440 |
| `when` | `{"count": 1}` | Up to three conditions, all of which must hold, below |
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
| `ratio` | matching events are at least a share of the events of `of` (by default: the same match without its text, regex and parameter conditions), with at least `minTotal` (10) of those | `{"ratio": {"atLeast": 0.5, "minTotal": 20}}` |
| `then` | a matching event is followed by an event of `then.match` within `within` minutes (60), on the same `session`, `user`, `request` or `param:<name>` if `same` is given. Combines with `count` only | `{"then": {"match": {"source": "error"}, "within": 30, "same": "user"}}` |
| `absent` | no matching event for `for` minutes; with `groupBy`, a group seen within `lookback` minutes (1440) has gone silent. Stands alone | `{"absent": {"for": 30}}` |
| `new` | the group appears in the window but not in the `baseline` days before it (7, up to 30). Needs `groupBy` | `{"new": {"baseline": 30}}` |
| `spike` | the window's count is at least `factor` times the usual count of the same window on the previous `days` days (7, up to 14), and at least `minCount` (10) | `{"spike": {"factor": 3}}` |

A problem clears when its condition has not held for `clearAfter` minutes. An `absent` problem clears
when a matching event arrives. Disabling or deleting a rule clears its problems.

### Summary

`summary` may use `{rule}`, `{group}`, `{count}`, `{users}`, `{value}`, `{total}`, `{ratio}`,
`{baseline}`, `{window}`, `{for}`, `{lookback}`, `{first}`, `{last}` and `{message}` (the newest
matching event's message). Without a summary, Datagrok writes one from the condition.

## Test before you save

**Test** in Settings, or `grok s observe rules test`, runs the rule over the last 24 hours (or fewer,
`--hours`) without raising anything: how many events it matched, the groups it holds for now, and the
groups it would have raised at any hour.

```bash
grok s observe rules test --json failed-logins.json
grok s observe rules add --json failed-logins.json
grok s observe rules list
```

## Examples

| Rule | What it catches |
|---|---|
| `failed-logins-per-user` | one account failing to sign in again and again |
| `package-error-spike` | a package suddenly erroring three times as often as on a usual day |
| `query-timeouts` | a connection whose queries keep timing out |
| `function-failed-twice` | a function that failed, was run again and failed again |
| `connection-monitor-silent` | the connection checks have stopped (a deployment rule: it pages the platform) |
| `chem-error-many-users` | one Chem error hitting five users within 15 minutes |
| `new-package-version-errors` | the first error from a package version (recorded, not alerted) |
| `slow-connection-checks` | a data connection answering slowly on average |
| `partner-bulk-downloads` | a member of the External partners group opening many files |

```json
[
  {"name": "failed-logins-per-user", "severity": "warning",
   "match": {"source": "audit", "type": "user-login-failed"},
   "groupBy": "param:login", "window": 15, "when": {"count": 5},
   "summary": "{count} failed logins for {group} in {window} min"},

  {"name": "package-error-spike", "severity": "warning",
   "match": {"source": "error", "params": [{"name": "packageName", "op": "exists"}]},
   "groupBy": "param:packageName", "window": 60, "every": 10,
   "when": {"spike": {"factor": 3, "days": 7, "minCount": 20}},
   "summary": "{group}: {count} errors in the last hour, {baseline} on a usual day"},

  {"name": "query-timeouts", "severity": "warning",
   "match": {"source": "error", "text": ["timeout"], "params": [{"name": "connection", "op": "exists"}]},
   "groupBy": "param:connection", "window": 60, "when": {"count": 10},
   "summary": "{count} query timeouts on {group} in the last hour"},

  {"name": "function-failed-twice", "severity": "warning",
   "match": {"source": "error", "params": [{"name": "function", "op": "exists"}]},
   "groupBy": "param:function", "window": 60,
   "when": {"then": {"match": {"source": "error"}, "within": 60, "same": "param:function"}},
   "summary": "{group} failed, ran again and failed again within an hour"},

  {"name": "connection-monitor-silent", "severity": "critical", "audience": "platform",
   "match": {"source": "audit", "type": "connection-checked"},
   "when": {"absent": {"for": 30}},
   "summary": "No connection check for {for} min: the connection monitor is not running"},

  {"name": "chem-error-many-users", "severity": "critical",
   "match": {"source": "error", "params": [{"name": "packageName", "op": "=", "value": "Chem"}]},
   "groupBy": "signature", "window": 15, "when": {"users": 5},
   "summary": "{users} users hit the same Chem error in {window} min: {message}"},

  {"name": "new-package-version-errors", "severity": "info",
   "match": {"source": "error", "params": [{"name": "packageVersion", "op": "exists"}]},
   "groupBy": ["param:packageName", "param:packageVersion"], "window": 60, "every": 15,
   "when": {"new": {"baseline": 30}},
   "summary": "First error from {group}: {message}"},

  {"name": "slow-connection-checks", "severity": "warning",
   "match": {"source": "audit", "type": "connection-checked", "params": [{"name": "status", "op": "=", "value": "ok"}]},
   "groupBy": "param:connection", "window": 60,
   "when": {"count": 3, "value": {"param": "ms", "agg": "avg", "op": ">=", "threshold": 5000}},
   "summary": "{group} answers in {value} ms on average"},

  {"name": "partner-bulk-downloads", "severity": "warning",
   "match": {"source": "usage", "type": "file-open", "groups": ["External partners"]},
   "groupBy": "user", "window": 60, "when": {"count": 200},
   "summary": "{group} opened {count} files in an hour"}
]
```

## Limits

| Limit | Value |
|---|---|
| Enabled rules | 50 |
| Problems raised per rule at a time | 100; beyond that, a `problem-rule` problem says so |
| One evaluation | 10 seconds per query |
| A test | 30 seconds, the last 1 to 24 hours |
| Sizes | 10 parameters, 10 keywords, 20 types, 50 users, 10 groups, 50 `in` values, 3 conditions |

A rule that is invalid, fails, or exceeds a limit raises a `problem-rule` problem for its owners
until it evaluates again.

## Rules the deployment defines

Put rules in the top-level `problemRules` key of [`GROK_PARAMETERS`](../../deploy/configuration.md)
(Helm: `datagrok.grokParametersExtra.problemRules`). They are listed as read-only in Settings and the
CLI, and only they may use `"audience": "platform"`. A deployment rule with the name of a rule made in
Settings replaces it.

```json
{
  "problemRules": [
    {"name": "connection-monitor-silent", "severity": "critical", "audience": "platform",
     "match": {"source": "audit", "type": "connection-checked"}, "when": {"absent": {"for": 30}}}
  ]
}
```

## What leaves the instance

A rule's alerts are the same records as any alert (see [where alerts go](problems-and-alerts.md#where-alerts-go)):
they carry the rule's kind (`rule-<name>`), the group as the alert key, the severity, the audience and the summary.
Keep personal data out of `groupBy` and `summary` if your monitoring system should not see it.
