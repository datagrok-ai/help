---
title: "Audit"
mdx:
  format: mdx
sidebar_position: 2
toc_max_heading_level: 3
unlisted: false
description: How Datagrok records, stores, and exports audit logs of user and system activity across entities.
keywords:
  - audit log
  - activity log
  - track usage
  - event logging
  - cloudwatch export
  - audit record types
  - entity history
---

In Datagrok, users can perform a wide range of tasks, from self-service data analytics to using custom applications. Datagrok's audit system provides detailed insights into how
users interact with the platform. With this knowledge, you can:

* Improve UX
  * Remove unused menu items, etc.
* Understand your users better
  * Cluster usage by usage patterns
  * Correlate usage patterns with the organizational groups
* Track data history
  * Track origin of datasets
  * See history of modifications
  * See all actions performed on an [object](../../datagrok/concepts/objects.md)
* Analyze performance
  * See how long each operation takes
* Analyze function usage
  * Get a table of users, timestamps, inputs and outputs
* Track errors
  * See all errors across the platform
  * Identify actions that cause errors

## Audit log storage

Datagrok automatically records and stores all user actions performed on
[entities](../../datagrok/concepts/objects.md) in a structured format within a
[Postgres database](../../develop/under-the-hood/architecture.md#data-engine),
making it easy to query and analyze specific events. The audit data is stored in
the following tables:

* `events`
* `event_types`
* `event_parameters`
* `event_parameter_values`

Each event is associated with a fixed type and the user session that triggered it.

<details>
<summary> Audit record types</summary>

* query-created
* query-edited
* query-deleted
* query-start
* query-published
* query-transformations-edited
* connection-created
* connection-edited
* connection-deleted
* connection-published
* connection-raw-write
* job-created
* job-edited
* job-deleted
* job-transformations-edited
* job-start
* script-created
* script-edited
* script-deleted
* script-start
* script-published
* predictive-model-created
* predictive-model-edited
* predictive-model-deleted
* predictive-model-start
* predictive-model-published
* action-start
* notebook-created
* notebook-edited
* notebook-deleted
* notebook-start
* notebook-published
* project-created
* project-edited
* project-deleted
* project-opened
* docker-image-created
* docker-image-rebuilt
* docker-image-deleted
* docker-container-created
* docker-container-edited
* docker-container-started
* docker-container-stopped
* docker-container-action-failed
* docker-container-deleted
* docker-container-config-created
* docker-container-config-deleted
* package-created
* package-edited
* package-deleted
* package-version-published
* package-version-activated
* sync-setup-created
* sync-setup-edited
* sync-setup-deleted
* user-report-created
* user-applied
* entity-shared
* entity-shared-silent
* user-invited
* comment-posted
* dialog-ok
* main-menu-item-click
* error
* tutorial-completed
* viewer-rendered
* log
* package-tested
* alert-opened
* alert-escalated
* alert-cleared
* alert-acknowledged
* alert-reopened
* alert-resolved
* problem-status-changed
* connection-checked
* user-error
* client-audit
* key.material.delete
* key.revoke.immediate
* key.revoke.force
* key.revoke.queued
* key.rotation.start
* key.rotation.complete
* key.rotation.auto
* server-started
* user-logged-in
* user-logged-out
* user-login-failed
* user-impersonated
* impersonation-failed
* admin-session-started
* admin-session-ended
* dev-key-generated
* email-confirmation-requested
* email-confirmed
* email-confirmation-failed
* password-reset-requested
* password-changed
* password-change-failed
* settings-changed
* log-settings-changed
* group-members-changed
* permission-granted
* permission-revoked
* credentials-saved
* admin-sql-executed
* privileged-call

</details>

The seventeen from `server-started` to `log-settings-changed` are the platform's own security trail — who
logged in and out, whose login failed and why, impersonation, admin sessions, developer keys, e-mail
confirmations, password resets and changes, settings
changes, and server starts. They are listed on the **System Activity** tab of [Usage Analysis](usage-analysis.md).

The last six record who can reach what: group membership changes (made in Datagrok or synced from an
identity provider), permissions granted and revoked, credentials saved (the names of the saved fields,
never their values), SQL run on the platform's own database connections, and functions called in an
admin or impersonated session.

Passwords, tokens, keys, and other secrets are replaced with `[REDACTED]` in event messages and parameters
before they are printed, stored, or exported.

## Accessing audit logs

You can access audit logs in a number of ways:
* From the [Context Panel](../../datagrok/navigation/panels/panels.md#context-panel)
  * **Activity**: This [info pane](../../datagrok/navigation/panels/info-panels.md) shows server-side activity for the current entity over the past seven days
  * **Usage**: This info pane shows a high-level overview of server-side usage for the current entity in the last seven days
* From the [Console](../../datagrok/navigation/panels/panels.md#console)
* From a Datagrok app, [Usage Analysis](usage-analysis.md)
* In your own log backend, such as Amazon CloudWatch, Google Cloud Logging, or any
  OpenTelemetry collector (see [Export logs](#export-logs))

### Export logs

Log events are sent to external destinations as they are posted, without waiting for them to be saved to the
database. Destinations are set up in **Browse** > **Platform** > **Health** > **Log settings**:

1. Under **Endpoints**, click **+** and fill in where to send (see the table below). An endpoint only describes a
   destination; nothing is sent to it yet.
1. Under **Log groups**, open a group, or click **+** for a new one, and tick the endpoint in **Save to**.
1. Click **Save** in the toolbar.

A group picks the records it sends by **Levels**, **Who** (users or groups; everyone by default) and an optional
**Filter**. For example, send errors to one CloudWatch log group and audit events to another: two groups, each
saving to its own endpoint.

<details>
<summary>Endpoint settings</summary>

| Setting        | Applies to            | Description                                                                                          |
|----------------|-----------------------|------------------------------------------------------------------------------------------------------|
| **Name**       | All                   | How log groups refer to the endpoint                                                                 |
| **Format**     | All                   | `json` (one object per event, queryable in the backend) or `text`                                     |
| **Cloud**      | All                   | **Amazon CloudWatch**, **Google Cloud Logging**, or **OpenTelemetry (OTLP)**                          |
| **Connection** | All                   | An AWS or GCP connection with write access. Leave empty to authenticate with the instance role       |
| **Log Group**, **Stream** | Amazon CloudWatch | Destination log group and stream. Without a connection, Datagrok creates them if they don't exist. With a connection, create them first |
| **Log Name**   | Google Cloud Logging  | Destination log                                                                                       |
| **Endpoint**   | OpenTelemetry         | OTLP/HTTP logs endpoint, for example `http://otel-collector:4318/v1/logs`                             |
| **Auth**       | OpenTelemetry         | `none`, `bearer` (with **Token**), `aws-sigv4`, or `gcp-oauth`                                        |
| **Headers**, **Compress**, **Max Payload** | OpenTelemetry | Extra HTTP headers, gzip compression, and the size at which a batch is split          |

</details>

To send problem and alert records to a collector that pages someone, add a group of kind **Alerts** that saves
to its endpoint: it takes the opened, escalated, resolved and still-firing records and the heartbeat, whatever
the levels of the other groups.

Besides regular events, the server emits alert records and a heartbeat that let your monitoring system page
you when a [problem](problems-and-alerts.md) starts. The records, when they arrive, and the problems behind
them are in the [operator guide](operator-guide.md#what-arrives-and-when). `alert-firing` and `heartbeat` aren't
stored in the database. They exist only in Log sync destinations.

To learn more, see [Export logs to Amazon CloudWatch](../../datagrok/solutions/teams/it/log-export-cloud-watch.md).

:::note

On a platform-managed instance, the **Log sync** section is hidden. The deployment owns the destinations.

:::

### Retention

By default, Datagrok keeps all events. To delete old events automatically,
turn on the **Garbage Collector** in **Settings** > **Admin**. It removes audit
events after 365 days, errors, warnings, info, and usage events after 183 days,
and debug events after 30 days. You can change each period. To keep events
longer, [export them](#export-logs) to a backend with its own retention policy.

### Integrity

Events live in the Datagrok database, so whoever can change the database can change them. To keep a copy that no
one can alter or delete, administrators included, export the log to write-once storage:

1. Create an S3 bucket with Object Lock turned on at creation, in `COMPLIANCE` mode, with a default retention of
   the period you must keep audit evidence (for example, 400 days). `GOVERNANCE` mode can be bypassed by a
   privileged account. Don't add a lifecycle rule that expires objects sooner, and never delete the bucket's KMS key.
1. Run an [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) with an OTLP/HTTP receiver behind
   TLS and a bearer token, and the `awss3` exporter (`marshaler: otlp_json`, `compression: gzip`) writing to that
   bucket. Keep the AWS SDK's default checksum behavior: Object Lock rejects uploads without a checksum.
1. In [Log sync](#export-logs), add an **OpenTelemetry** destination pointing to the collector, with **Auth** set
   to `bearer` and at least the `audit` level selected.

Turning a destination off or deleting it is itself sent to that destination before the change applies. If a
destination drops records or keeps failing, Datagrok raises an `export` problem until it delivers again.

## Logging events

Datagrok logs both client-side and server-side activities. 

### Client-based actions

Thanks to Datagrok's [in-memory database](../../develop/under-the-hood/performance.md#in-memory-database), many
user activities related to exploratory data analysis, such as opening local
files, aggregating tables, or adding viewers, occur entirely on the client.
These actions generate internal named events that serve various purposes:

* Integration of different Datagrok components
* Ad-hoc customizations and extensions by plugins
* Audit logs

Datagrok logs a reasonable default set of client-based actions. For example, it
logs the opening of a file and its name, but not the content. Less important
actions, like "rows selected", aren't logged. To learn how to customize what
gets logs, see [Customize audit logging](#customize-audit-logging).

### Server-related actions

When an action modifies the server's state in any way, it's recorded in the
audit log in addition to the log file. You can see a seven-day history of such
activity on the **Context Panel** under **Activity**, and the
high-level overview of the entity's usage under **Usage**.

By default, each explicitly executed
[function](../../datagrok/concepts/functions/functions.md) is logged,
along with its parameter values.

## Customize audit logging

To customize which events are logged and how they are handled, you have these options:

1. Configure logging settings: For any user or group, add or remove logged
   events from the default set
1. Create custom logging events and make other customizations using [JS API](#customizing-logging-via-javascript-api)

### Changing settings for default logs

What is logged is set in **Browse** > **Platform** > **Health** > **Log settings**
(**Settings** > **Logger** opens the same page). It has three parts:

* **Log groups**, read top to bottom. Each group picks records and sends them to its destinations (the Datagrok
  database, the console, or an [endpoint](#export-logs)). A record reaches a destination once. A group is one of:
  * **Records**: what users and the server log, of the ticked **Levels**, from **Who** (everyone by default),
    narrowed by debug flags, audit or usage types, and a **Filter**.
  * **Alerts**: problem and alert records, for collectors that page someone.
  * **Drop**: matching records go nowhere; groups below it don't see them. Put it above the groups it silences.

  A group is active **Always**, **Until** a time, or **When triggered** by a record (for example, keep debug records
  of a session for ten minutes after it hits an error). The **Audit export** group takes every audit record and
  can only be changed with the Edit Audit Logging permission.
* **Endpoints**: the external destinations, see [Export logs](#export-logs).
* **Buffer**: the recent records each server process keeps in memory per level, whatever is saved, and for how
  long. A triggered group sends them along with the record that switched it on; error reports include them.

Hover a part's header for what it is and which values are fine. Click **Save** to apply. On a platform-managed
instance the page is read-only: the deployment owns the settings.

### Customizing logging via JavaScript API

To customize audit logs using Datagrok's JavaScript API:

1. Create a `Logger` object:

     ```javascript
     // Create logger
     let logger = new DG.Logger();
     // You can pass a callback that sets predefined parameters
     let logger = new DG.Logger((m) => m.params['persistent']= 'value');
     ```

1. To log events, use the `logger.log()` method:

     ```javascript
     // Default type is "log"
     logger.log('HELLO WORLD', {test: 'value', 'foo': 'bar'});
     // But you can specify another
     logger.log('HELLO WORLD', {test: 'value', 'foo': 'bar'}, 'my_log');
     ```

1. Errors are logged automatically, but you can log them explicitly and specify
   the stack trace for grouping errors:

     ```javascript
     // Specify stack trace to group errors
     logger.error('Error!', stackTrace);
     ```

See [this sample](https://public.datagrok.ai/js/samples/ui/ui-events)
for a demonstration of how to handle events.