---
title: "Promote content between instances"
sidebar_label: "Promote content"
sidebar_position: 0.5
description: How to move dashboards, spaces, queries, connections, and other content built in the UI from one Datagrok instance to another with the grok s CLI, from a single dashboard to a whole instance.
keywords:
  - dev to prod promotion
  - move content between instances
  - migrate dashboards
  - grok s migrate
  - grok s pull
  - grok s push
  - content bundle
---

Teams usually build dashboards, queries, and connections on a dev or test
instance and then move them to production. This page shows how to move content
built in the UI with the [`grok s`](../develop/server-management.md) CLI, from a
single dashboard to a whole instance.

## Choose the path

| Content                                                  | How to move it                                                                         |
|----------------------------------------------------------|----------------------------------------------------------------------------------------|
| Kept in Git as a package (business-critical content)      | Publish the same package version to each instance: `grok publish <instance> --release` |
| Built in the UI: dashboards, spaces, queries, scripts...  | Move it with `grok s`, as described on this page                                       |

`grok s` moves connections, queries (including visual queries), scripts,
dashboards and spaces, views and layouts, tables with their data, files, jobs,
notebooks, models, and the groups and permissions they need.

## How it works

Content travels as a **bundle**: a folder with one JSON file per entity, plus
the data of the tables. You can review a bundle, commit it to Git, and push it
again later.

```bash
grok s pull Chem:TargetDashboard --out ./release --host dev   # instance → folder
grok s diff ./release --host prod                             # what a push would change
grok s push ./release --host prod --dry-run                   # print the plan only
grok s push ./release --host prod                             # folder → instance
grok s migrate Chem:TargetDashboard --from dev --to prod      # pull and push in one step
```

* **Dependencies come along.** A dashboard brings its tables, views, and
  layouts, a query brings its connection, and every entity brings the groups
  that hold permissions on it.
* **IDs are kept.** Entities keep the same ID on both instances, so pushing
  again updates what is already there, and an unchanged entity is not written
  at all.
* **The source is only read.** Nothing on the instance you pull from changes.

`--from`, `--to`, and `--host` take the server aliases from
`~/.grok/config.yaml` (see [Configuration](../develop/server-management.md#configuration)).

## Prepare the target

Some things belong to the instance rather than to a bundle, so they have to be
in place before the first push:

| What                     | Why                                                                                | How                                                                                     |
|--------------------------|------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| An administrator account | Without `--admin`, a run sees and places only the content its own account can reach | Use an account in the Administrators group on both instances                            |
| Users                    | Content of a user who doesn't exist on the target is saved under the pushing account | Create the users on the target first                                                   |
| Packages                 | Content that calls package functions needs the package on the target              | Publish the packages: `grok publish <target> --release`                                 |
| Credentials              | Passwords never travel                                                             | Prepare a credentials file (see below), or enter the passwords in the UI after the push |
| A backup                 | A push can't be undone                                                             | [Back up](../deploy/complete-setup/backup.md) the target before a large move            |

If you have a staging instance that mirrors production, try the move there
first.

Passwords go into a YAML file written for the target, with values taken from
environment variables:

```yaml
# creds.yaml: keys are the connection names as the bundle spells them
Chem:Chembl:
  password: ${CHEMBL_PROD_PASSWORD}
```

```bash
CHEMBL_PROD_PASSWORD=... grok s migrate Chem:TargetDashboard --from dev --to prod --creds ./creds.yaml
```

## Move a dashboard

1. See what would change, without writing anything:

   ```bash
   grok s migrate Chem:TargetDashboard --from dev --to prod --dry-run
   ```

2. Move it:

   ```bash
   grok s migrate Chem:TargetDashboard --from dev --to prod --creds ./creds.yaml
   ```

3. Run the same command again. Every entity should now be reported as
   `identical`, and nothing is written.

To move a space with everything in it, select the space: `--space Chem`. Select
the space itself rather than the items in it, so that they keep their place in
it. You can also select with `--type`, `--author`, `--tag`, `--name`, or
`--since`.

To keep a bundle under version control, pull and push in separate steps:

```bash
grok s pull Chem:TargetDashboard --out ./release --host dev
git add release && git commit -m "release: target dashboard"
grok s push ./release --host prod --creds ./creds.yaml
```

A bundle remembers which entities it matched on the instance it was pushed to.
To push to a different instance, pull into a new folder.

## Move an instance

To move all the content of an instance, move it one space at a time. Each space
is its own pull and push, so a failure affects one space rather than the whole
run.

1. See the plan. The run first lists the users and packages the target is
   missing, and doesn't start until they are in place:

   ```bash
   grok s migrate --from dev --to prod --admin --by-namespace --on-conflict adopt --dry-run
   ```

2. Run it:

   ```bash
   grok s migrate --from dev --to prod --admin --by-namespace --on-conflict adopt \
     --creds ./creds.yaml --state ./migration-state.json
   ```

3. If the run stops, run the same command again. The state file records the
   spaces that finished, and the next run continues with the rest.

To move only some spaces, add `--only Chem,Bio`, or leave spaces out with
`--skip`. Layouts and views that belong to no space are moved only by a run
without `--only`.

A move of a few dashboards takes minutes, and a move of a whole instance can
take hours. Select dashboards and spaces rather than tables: the tables they use
come along, and tables that nothing uses stay behind.

### Name conflicts

An entity whose name exists on the target under a different ID is a conflict.
`--on-conflict` decides what happens:

| `--on-conflict`  | Result                                                             | Use it                                         |
|------------------|--------------------------------------------------------------------|------------------------------------------------|
| `fail` (default) | Nothing is written. All conflicts are listed                       | To review the conflicts first                  |
| `adopt`          | The bundle entity is written into the existing one                 | To update what the target already has (usual) |
| `skip`           | The existing entity is kept, and anything that depends on it fails | To keep the target's version                   |
| `duplicate`      | A second copy is created next to the existing one                  | To keep both versions                          |

## Check the result

1. Run the same move again. Every entity should be `identical`. A run with a
   `failed` row exits with an error.
2. Open the main dashboards on the target. Check that they are in their spaces
   and show their data and layouts.
3. Check the sharing of a few key dashboards and spaces.
4. Test the connections on the target.

## What doesn't travel

| What                       | What to do                                                             |
|----------------------------|------------------------------------------------------------------------|
| Passwords and other secrets | Pass `--creds`, or enter them in the UI on the target                  |
| Users                      | Create them on the target first                                        |
| Package content            | Publish the package to the target                                      |
| Files inside file shares   | Copy the storage behind the share. Only standalone files are moved     |
| Removals                   | A push only adds and updates. Remove what's no longer needed in the UI |
| Trained model files        | Retrain or upload the model on the target                              |

Tables built by joining or aggregating other tables move with their data, but
to refresh them, the target needs their source tables too.

## See also

* [Manage an enterprise instance](manage-enterprise.md#promote-content)
* [Manage the server with `grok s`](../develop/server-management.md)
* [Full `grok s` reference](https://github.com/datagrok-ai/public/blob/master/tools/GROK_S.md#migrating-entities-between-instances-pull--push--migrate)
