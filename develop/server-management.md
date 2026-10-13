---
title: "Server management with grok s"
sidebar_position: 6
keywords: [grok, cli, server management, automation, integration, ldap, active directory]
---

`grok s` (alias of `grok server`) is a command-line tool for managing a running
Datagrok server over its [public REST API](packages/rest-api.md). Use it to
create, update, share, or inspect entities on the server: users, groups,
connections, queries, scripts, packages, files, and function calls. It also
suits bulk operations and integrations that should not depend on a browser.

`grok s` ships with [`datagrok-tools`](https://www.npmjs.com/package/datagrok-tools).
Install with `npm install -g datagrok-tools`, then configure a server.

## When to use grok s

| Task                                                       | Command                                                    |
|------------------------------------------------------------|------------------------------------------------------------|
| Create or update a user                                    | `grok s users save --json user.json`                       |
| Block or unblock a user                                    | `grok s users block <login>` / `users unblock <login>`     |
| Create or update a group                                   | `grok s groups save --json group.json`                     |
| Add members to a group                                     | `grok s groups add-members <group> <user>...`              |
| Remove members from a group                                | `grok s groups remove-members <group> <user>...`           |
| List members of a group                                    | `grok s groups list-members <group>`                       |
| List the groups a user belongs to                          | `grok s groups list-memberships <user>`                    |
| Share a connection, query, script, or project with a group | `grok s shares add <entity> <group> [--access View\|Edit]` |
| Create or update a connection                              | `grok s connections save --json conn.json`                 |
| Test a connection                                          | `grok s connections test <id-or-name>`                     |
| Run a registered function                                  | `grok s functions run 'Pkg:fn(arg1,arg2)'`                 |
| List or browse files in a file share                       | `grok s files list "System:AppData" -r`                    |
| Upload or download a table (CSV)                           | `grok s tables upload <name> file.csv`                     |
| Check whether a package is deployed                        | `grok s packages list --filter "MyPlugin"`                 |
| Install, update, or uninstall plugins                      | `grok s packages install Chem Bio` / `packages update --all` |
| See installed vs latest plugin versions                    | `grok s packages outdated`                                 |
| Hit any undocumented endpoint                              | `grok s raw GET /api/users/current`                        |
| Check server and per-module health                         | `grok s healthcheck [--module <name>]`                     |
| Bulk operations in one round-trip                          | `grok s batch <entity> <verb> --json items.json`           |
| Promote content from dev to production                     | `grok s migrate <entity> --from dev --to prod`             |

## Configuration

Servers and developer keys live in `~/.grok/config.yaml`:

```yaml
default: local
servers:
  local:
    url: http://localhost:8888/api
    key: admin
  dev:
    url: https://dev.datagrok.ai/api
    key: <developer-key>
```

To add a server, run `grok login <server>`. It enrolls a keypair and writes the entry for you, with an
empty `key:` field. See [Keypair authentication](../govern/access-control/keypair-authentication.md).
Pass `--host <alias-or-url>` to any `grok s` command to override the default.

The developer key is deprecated. As a legacy fallback, copy it from **Developer key...** on your profile and add
an entry with `grok config add --alias <name> --server <url> --key <key>`. Datagrok 1.28 and later accept the
developer key only from datagrok-tools 6.6.0 or later.

## Common workflows

### Manage users and groups

```bash
grok s users list                                    # default: table, 50 rows
grok s users list --filter "status = 'active'"       # smart filter
grok s users save --json user.json                   # create or update
grok s users block alice.mendel                      # accepts a login, email, or UUID

grok s groups save --json group.json
grok s groups add-members Chemists alice.mendel bob.curie
grok s groups add-members Admins analysts            # nest a group inside a group
grok s groups list-members Chemists --no-admin
grok s groups list-memberships alice.mendel
```

`add-members` is idempotent: each member is resolved (by login, name, or UUID),
compared against the group's current children, and only written when something
changes. Pass `--user` to disambiguate a name as a personal group.

### Share entities

```bash
grok s shares add "MyUser:MyConnection" Chemists,Biologists --access Edit
grok s shares list <entity-uuid>
```

The entity argument accepts either a UUID or a `"namespace:name"` pair.
`--access` defaults to `View`.

### Run functions

```bash
grok s functions run 'Chem:smilesToMw("CCO")'                  # positional args
grok s functions run 'Pkg:fn({smiles:"CCO", radius:2})'        # named args
grok s functions run Pkg:fn --json params.json                 # big input from a file
```

### Browse files and tables

```bash
grok s files list "System:AppData" -r
grok s files put ./smiles.csv "System:DemoFiles/smiles.csv"

grok s tables upload MyTable ./data.csv
grok s tables download MyTable -O ./data.csv
```

`files put` sends the file as raw bytes, without base64 or JSON wrapping. The CLI
reads the whole file into memory first. `tables upload` registers a proper
Datagrok [table entity](../datagrok/concepts/objects.md) and returns its ID.

### Manage packages

Install, update, and remove server [plugins](../datagrok/plugins.md) the same way
the Package Manager UI does. The server pulls released versions from its
configured package repository (npm):

```bash
grok s packages install Chem Bio PowerGrid       # install the latest of each
grok s packages install Chem --version 1.14.0    # pin a specific version
grok s packages outdated                         # installed vs registry-latest
grok s packages update --all                     # upgrade everything outdated
grok s packages versions Chem                    # published versions and flags
grok s packages set-version Chem 1.13.0          # activate a specific version
grok s packages uninstall Chem                   # a repository package stays installable
grok s packages share Chem Chemists --access View
```

`install` without `--version` sets the package to `latest`, an auto-update intent
the server re-resolves against the registry every 15 minutes. A pinned version
stays put until you change it. Install is synchronous and idempotent. If a heavy
first-time install times out, re-run it. Publishing your own package sources is
still [`grok publish`](how-to/packages/create-package.md).

### Server health

```bash
grok s healthcheck                             # full per-module health
grok s healthcheck --module Jupyter            # filter to one module
grok s healthcheck --output json               # machine-readable
```

The server runs its health checks every 60 seconds: **Core** (the database
and the server isolates), **Grok Connect**, **Jupyter**, **Credentials
Server**, **Garbage Collector**, **Message Queue** (when the call queue is
enabled), and **Grok Spawner**. You can see the same results on the **Health** page of the setup wizard,
which stays available at `/settings/initial/health`.
Two endpoints expose them, both under the API root (for example,
`https://datagrok.example.com/api`):

| Endpoint                     | Sign-in  | Caching          | Response                                                                 |
|------------------------------|----------|------------------|--------------------------------------------------------------------------|
| `GET /admin/health`          | Not required | Up to 60 seconds | JSON array, one object per service                                  |
| `GET /public/v1/healthcheck` | Required | None             | `{status, server, version, time, services}`, where `services` is the same array |

Both accept `?module=<key>` to return a single service. Each service object has
`key`, `type`, `name`, `description`, `enabled`, `time`, `nextCheck`,
`intervalSeconds`, `lastSuccess`, and `status`, plus `error` when the check
failed and `postponedSince` when it is postponed. `status` is one of:

| Status             | Meaning                                                      |
|--------------------|--------------------------------------------------------------|
| **Running**        | The last check passed                                        |
| **Failed**         | The last check failed. See the `error` field                 |
| **Stopped**        | The service is turned off                                    |
| **Not applicable** | The service isn't part of this deployment                    |
| **Postponed**      | The check is waiting, for example for the service to start    |

`/public/v1/healthcheck` sets `status` to `degraded` when any service is
**Failed**, and to `ok` otherwise. It always answers with HTTP 200, so monitors
must read `status` from the body.

Use `/admin/health` for anonymous probes, such as load balancer health checks
and Kubernetes readiness probes. Use `/public/v1/healthcheck` or
`grok s healthcheck` for synthetic monitoring that needs the version and an
overall status.

### Raw API access

```bash
grok s raw GET /api/users/current
```

On Windows Git Bash, prefix with `MSYS_NO_PATHCONV=1` so the shell does not
rewrite POSIX paths.

## Scripting patterns

`--output quiet` and `--output json` make `grok s` safe to compose with shell
tooling:

```bash
grok s users list --filter "status = 'active'" --output quiet \
  | xargs -I{} grok s users get {}

grok s connections list --output json \
  | jq '.[] | select(.dataSource=="Postgres") | .name'
```

`add-members`, `remove-members`, `shares add`, `packages install`, and `push` are
idempotent, so re-running them is safe. `users save` and `groups save` without
an `id` fail on a re-run because the entity already exists. Include the `id` to
update it instead.

## Move content between instances

To promote content built in the UI, such as connections, queries, scripts,
dashboards, spaces, and layouts, from one instance to another (for example,
from dev to production), use `grok s pull`, `diff`, `push`, and `migrate`.
Content travels as a *bundle*: a folder with one JSON file per entity that you can
review, commit to Git, and push again later.

```bash
grok s pull Chem:TargetDashboard --out ./release --host dev   # instance → folder
grok s diff ./release --host prod                             # what a push would change
grok s push ./release --host prod --dry-run                   # print the plan only
grok s push ./release --host prod --creds ./creds.yaml        # folder → instance
grok s migrate Chem:TargetDashboard --from dev --to prod      # pull and push in one step
```

For the steps, including preparing the target, moving a whole instance, name
conflicts, and what doesn't travel, see
[Promote content between instances](../govern/promote-content.md).

## Sync an AD group with Datagrok

A common integration scenario: add the members of an Active Directory group to a
Datagrok group. Pull the AD members from your directory of choice, then drive
Datagrok with `grok s`:

```bash
# 1. Create the Datagrok-side group (a re-run fails with "already exists").
cat > /tmp/g.json <<'EOF'
{ "#type": "UserGroup", "name": "Chemists", "friendlyName": "Chemists" }
EOF
grok s groups save --json /tmp/g.json

# 2. Create the users, one per logon name from AD (an existing login fails with "already exists").
for row in alice.mendeleev:Alice:Mendeleev bob.curie:Bob:Curie ; do
  IFS=: read -r login first last <<<"$row"
  cat > /tmp/u.json <<EOF
{ "#type": "User", "login": "$login", "firstName": "$first", "lastName": "$last", "status": "active" }
EOF
  grok s users save --json /tmp/u.json --output quiet
done

# 3. Add the members in one call (idempotent: existing members are skipped).
#    Members who left AD stay in the group: remove them with groups remove-members.
grok s groups add-members Chemists alice.mendeleev bob.curie --user

# 4. Verify.
grok s groups list-members Chemists --no-admin
```

Combine with the [LDAP authentication setup](../deploy/complete-setup/configure-auth.md#ldap-authentication)
to let the same users sign in with their AD credentials.

## Full reference

The page above covers the most common tasks. For the exhaustive command
reference (JSON shapes, batch manifests, `connections save --save-credentials`,
all output flags), see
[`tools/GROK_S.md`](https://github.com/datagrok-ai/public/blob/master/tools/GROK_S.md)
in the public repository.

## See also

* [REST API](packages/rest-api.md): the underlying HTTP surface
* [JavaScript API](packages/js-api.md): for in-platform plugin code
* [Users and groups](../govern/access-control/users-and-groups.md)
* [Configure authentication](../deploy/complete-setup/configure-auth.md)
* [Manage credentials](how-to/packages/manage-credentials.md)
