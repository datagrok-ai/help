---
title: "Set up a private package repository"
description: Keep your organization's Datagrok packages in one repository with semantic versioning, and deliver them through your npm registry (Artifactory, Nexus) or directly to Datagrok from CI.
keywords:
  - private packages
  - package repository
  - npm registry
  - Artifactory
  - Nexus
  - continuous integration
  - grok publish
  - GROK_PRIVATE_KEY
  - semantic versioning
---

Datagrok plugins are ordinary npm packages. You can manage your organization's packages the way
Datagrok manages its [public repository](https://github.com/datagrok-ai/public): one Git repository,
semantic versions in each `package.json`, and CI that builds, tests and publishes.

You can deliver packages to Datagrok in two ways, and you can use both:

| | Through your npm registry | Directly to Datagrok |
|---|---|---|
| CI runs | `npm publish` to Artifactory, Nexus or another npm registry | `grok publish` against a Datagrok instance |
| Datagrok gets the package | An administrator installs a version from the registry | Uploaded by CI |
| Best for | An auditable record of releases, rollbacks, several instances | No registry, fast "latest build on dev" loops |

## Repository layout

```
acme-datagrok/
├── packages/
│   ├── AcmeChem/            # one folder per Datagrok package
│   └── AcmeDashboards/
├── libraries/               # optional: TypeScript code shared between packages
├── pnpm-workspace.yaml      # packages/*, libraries/*
└── .github/workflows/       # or .gitlab-ci.yml, Jenkinsfile
```

* Create each package with [datagrok-tools](create-package.md): `npm install -g datagrok-tools`,
  then `grok create AcmeChem`.
* Give every package your own npm scope, for example `"name": "@acme/acme-chem"`. Datagrok finds
  packages in a registry by scope.

## Versioning

The package version is the `version` field in `package.json`. Use
[semantic versioning](../../dev-process/versioning-policy.md):

1. **Bump the version in the same pull request** as the change.
2. **Publish only versions that don't exist yet.** CI checks the registry and skips a version that
   is already there, so merging a change without a bump builds and tests it but releases nothing.
   This is how the Datagrok public repository works.
3. **Keep a `CHANGELOG.md`** in each package, so administrators can see what a version changes
   before they install it. See the [changelog policy](../../dev-process/changelog-policy.md).

Each published version is a separate entity in Datagrok. Administrators can switch between versions
and roll back to an older one (see [version control](../../develop.md#version-control)).

## Option A: npm registry

### Build and publish

Run this on every merge to your main branch, for each changed package:

```bash
npm ci                                  # or pnpm install
npm run build
grok test --host <test-stand>           # optional, recommended
VERSION=$(node -p "require('./package.json').version")
NAME=$(node -p "require('./package.json').name")
if ! npm view "$NAME@$VERSION" version > /dev/null 2>&1; then
  npm publish --registry https://artifactory.acme.com/artifactory/api/npm/npm-local/
fi
```

Configure registry authentication for `npm publish` the way your registry documents, usually an
`.npmrc` with an auth token stored as a CI secret.

### Connect the registry

An administrator does this once per Datagrok instance:

1. Open **Browse** > **Platform** > **Repositories** and add a package repository.
2. Set the fields:
   * **Registry**: the npm repository URL, for example
     `https://artifactory.acme.com/artifactory/api/npm/npm-local/`
   * **Scope**: `acme` (without the `@`)
   * **Credentials**: a login and password, sent as HTTP Basic authentication, or a token. Datagrok
     sends the token as the `Authorization` header exactly as you enter it, so include the scheme:
     `Bearer <token>`.
3. Datagrok lists every `@acme/*` package in the registry with its versions. Deprecated versions are
   hidden. Choose the version to install in the package manager.

The Datagrok server needs network access to the registry. If the server reaches the internet through
a proxy, configure the proxy in the server settings.

Datagrok lists packages with the standard npm search endpoint. Artifactory and Nexus both provide it
on npm repositories. To check that yours works with the credentials you gave Datagrok:

```bash
curl -H "Authorization: Bearer <token>" "https://artifactory.acme.com/artifactory/api/npm/npm-local/-/v1/search?text=@acme"
```

The response should list your packages.

## Option B: direct publish

`grok publish` builds a package and uploads it to a Datagrok instance. In CI, it signs in with a
[keypair](../../../govern/access-control/keypair-authentication.md), so no password or long-lived
API key is stored anywhere.

### CI identity

1. Create a service user for CI, for example `ci-bot`, with permission to publish packages.
2. Generate a key pair. For example, with Node:

   ```js
   const {generateKeyPairSync} = require('crypto');
   const {publicKey, privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
   console.log(JSON.stringify(publicKey.export({format: 'jwk'})));
   console.log(JSON.stringify(privateKey.export({format: 'jwk'})));
   ```

3. Sign in as `ci-bot`, open **Profile** > **Public keys...** > **Add a public key**, paste the public
   key and optionally set an expiration date.
4. Store the private key as a CI secret named `GROK_PRIVATE_KEY`. It can be raw JSON or
   base64-encoded.

### Publish from CI

GitHub Actions example:

```yaml
name: publish
on:
  push:
    branches: [main]
    paths: ['packages/**']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm install -g datagrok-tools
      - working-directory: packages/AcmeChem
        env:
          GROK_PRIVATE_KEY: ${{ secrets.GROK_PRIVATE_KEY }}
          GROK_LOGIN: ci-bot
        run: |
          npm ci
          grok publish https://datagrok.acme.com/api --release
```

The same commands work in GitLab CI, Jenkins or any other CI tool: set `GROK_PRIVATE_KEY` and
`GROK_LOGIN` in the environment and run `grok publish <server URL> --release`.

* Without `--release`, the package is a **debug** version that only the publishing user sees. With
  `--release`, it is available to everyone who has access to the package
  (see [publishing modes](../../develop.md#publishing-modes)).
* After the first publish, [share the package](publish-packages.md#private-packages) with the groups
  that should use it.

## Recommended setup

Combine the two options:

| Stage | Trigger | How the package gets there |
|---|---|---|
| Development instance | Every merge to the main branch | `grok publish <dev> --release` (option B) |
| Release | Version bump merged, or a Git tag | `npm publish` to your registry (option A) |
| Test and production instances | An administrator's decision | Install that version from the registry repository |

Developers see their changes on the development instance within minutes. Production only runs
versions that are in your registry and that an administrator chose to install.

## See also

* [Publish packages](publish-packages.md)
* [Create a package](create-package.md)
* [Keypair authentication](../../../govern/access-control/keypair-authentication.md)
* [Versioning policy](../../dev-process/versioning-policy.md)
