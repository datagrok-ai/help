---
title: "Set up Microsoft Entra ID"
sidebar_label: "Microsoft Entra ID"
sidebar_position: 1.5
description: Sign users in to Datagrok with Microsoft Entra ID (Azure AD) and sync their Entra groups into Datagrok groups.
keywords:
  - microsoft entra id
  - azure ad login
  - entra sso
  - entra group sync
  - app registration
---

This page walks you through connecting Datagrok to Microsoft Entra ID (formerly Azure AD), so that:

* Users sign in to Datagrok with their Microsoft work account.
* Their Entra group membership is mirrored into Datagrok groups, on login and on a schedule.

You need an Entra role that can register applications and grant admin consent, such as
**Application Administrator** or **Global Administrator**, and the Datagrok **Administrators** role.

For the general OpenID settings and other identity providers, see
[Configure authentication](configure-auth.md).

## Register the application

1. In the [Microsoft Entra admin center](https://entra.microsoft.com), go to **Identity** >
   **Applications** > **App registrations** and click **New registration**.
2. Fill in the form:
   * **Name**: for example, `Datagrok`.
   * **Supported account types**: **Accounts in this organizational directory only**.
   * **Redirect URI**: platform **Web**, URI `https://<your-datagrok-host>/oauth/openid/`. Keep the
     trailing slash. For a local server on `localhost`, use `http://localhost:<port>/oauth.html`.
3. Click **Register**.
4. On the application's **Overview** page, copy the **Application (client) ID** and the
   **Directory (tenant) ID**.

## Create a client secret

1. Go to **Certificates & secrets** > **Client secrets** and click **New client secret**.
2. Choose an expiry and click **Add**.
3. Copy the secret **Value** right away. Entra shows it only once. Don't copy the **Secret ID**.

Put a reminder in your calendar to rotate the secret before it expires: when it does, nobody can sign
in through Entra.

Instead of a secret, you can authenticate with a certificate. Upload the certificate under
**Certificates & secrets** > **Certificates**, and use the **AzureAD JWT** secret type in Datagrok
(see [OpenID authentication](configure-auth.md#openid-authentication)).

## Add the email claim

By default, Entra ID tokens don't carry the `email` claim.

1. Go to **Token configuration** and click **Add optional claim**.
2. Choose **ID**, select **email**, and click **Add**. If Entra asks to turn on the Microsoft Graph
   email permission, accept.

Entra fills this claim from the user's **Email** (mail) attribute. If your users have no mailbox, set
**Email Claim** in Datagrok to `preferred_username` instead. It holds the user's sign-in name, which
usually looks like an email address.

## Grant API permissions

Go to **API permissions**, click **Add a permission** > **Microsoft Graph**, and add the following:

| Type        | Permission             | Needed for                                                                 |
|-------------|------------------------|----------------------------------------------------------------------------|
| Delegated   | `openid`, `profile`, `email` | Sign-in                                                              |
| Delegated   | `User.Read`            | Sign-in                                                                    |
| Delegated   | `GroupMember.Read.All` | Reading the user's groups when they sign in                                |
| Application | `User.Read.All`        | Group sync for users who aren't signed in: finding the user by email       |
| Application | `GroupMember.Read.All` | Group sync for users who aren't signed in: reading the user's groups       |

Then click **Grant admin consent for &lt;your organization&gt;** and confirm. Every permission must
show a green **Granted** status.

If you only need sign-in, add just the first two rows and skip [Turn on group sync](#turn-on-group-sync).

:::tip Restrict who can sign in

By default, every user in your tenant can sign in to Datagrok. To allow only some users, go to
**Identity** > **Applications** > **Enterprise applications**, open the application, set
**Properties** > **Assignment required?** to **Yes**, and add users or groups under
**Users and groups**.

:::

## Configure Datagrok sign-in

1. In Datagrok, open **Settings** > **Admin** and make sure **Web Root** is the address users open,
   for example `https://<your-datagrok-host>`. Datagrok builds the redirect URI from it.
2. Open **Settings** > **Users and Sessions** and turn on **OpenID**.
3. Set the following:

   | Setting                | Value                                                                                         |
   |------------------------|-----------------------------------------------------------------------------------------------|
   | Configuration Endpoint | `https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration`         |
   | Client Id              | The Application (client) ID                                                                   |
   | Secret Type            | **Client Secret**                                                                             |
   | Client Secret          | The secret Value                                                                              |
   | Scopes                 | `openid profile email GroupMember.Read.All` (just `openid profile email` without group sync) |
   | Login Claim            | `preferred_username`                                                                          |
   | Email Claim            | `email`, or `preferred_username` for users without a mailbox                                  |
   | First Name Claim       | `given_name`                                                                                  |
   | Last Name Claim        | `family_name`                                                                                 |

   Use the tenant ID, not a domain name, in the configuration endpoint. Keep the endpoint on
   `login.microsoftonline.com`: Datagrok treats other hosts as generic OpenID providers and doesn't
   call Microsoft Graph for them.
4. Click **Save and apply** on the **Top Bar**.

To check sign-in, open Datagrok in a private browser window and click **Login with OpenID**. After
you sign in to Microsoft, Datagrok creates the user on first login, if
[signup](configure-auth.md#general-login-password-authentication) allows it. To send users to Microsoft
without showing the login form, turn on **Auto Login using OpenID**.

Keep a working administrator account with a password, or keep **Internal authentication** on, until
Entra sign-in works for an administrator. Otherwise a wrong setting can lock everyone out.

## Turn on group sync

Group sync mirrors the Entra groups a user belongs to, including nested groups, into Datagrok groups.
Groups are matched by display name, missing groups are created, and memberships the user no longer has
in Entra are removed. Groups and memberships that an administrator created by hand are never removed.
For details, see [Group synchronization](configure-auth.md#group-synchronization).

1. In **Settings** > **Users and Sessions** > **Group Sync**, turn on **Sync Groups**.
2. Set **Provider** to **Azure Entra**.
3. Set **Group Filter** to a regular expression that matches the groups you want in Datagrok, for
   example `^datagrok-` for groups whose names start with `datagrok-`. Matching ignores case. Leave
   it empty to sync every group the user belongs to.
4. Set **Sync Interval** to how often, in minutes, every user's groups are re-read from Entra. With
   `60`, a user removed from an Entra group loses the Datagrok group within an hour, even without
   signing in. Use `0` to sync on login only.
5. Click **Save and apply**.

To check the setup, enter a user's email next to **Test for user** and click **Test**. Datagrok reads
the user's groups from Entra and lists them. Groups that the filter excludes are greyed out. Below the
list, Datagrok shows the groups it currently manages for this user. The test uses the values on the
page before you save them, but the OpenID settings it uses must already be saved.

To sync everyone right away instead of waiting for the interval, click **Sync now**.

A user Entra has no record of keeps their Datagrok groups. If Entra can't be reached, nothing changes.

## Troubleshooting

| Symptom                                                                   | Cause and fix                                                                                                                                  |
|---------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `AADSTS50011` (redirect URI doesn't match)                                | The redirect URI in the app registration must equal **Web Root** + `/oauth/openid/`, including `https` and the trailing slash               |
| `AADSTS7000215` (invalid client secret)                                   | You copied the **Secret ID** instead of the secret **Value**, or the secret expired. Create a new secret                                    |
| `AADSTS65001` (consent required)                                          | Click **Grant admin consent** on the **API permissions** page                                                                                |
| User signs in, but gets the wrong login or no email                       | Set **Login Claim** to `preferred_username`, add the `email` optional claim, or set **Email Claim** to `preferred_username`                 |
| Test shows `Authorization_RequestDenied: Insufficient privileges`         | The **application** permissions `User.Read.All` and `GroupMember.Read.All` are missing or not consented                                     |
| Test says Entra has no record of the user                                 | The email doesn't match the user's sign-in name (UPN) or **Email** attribute in Entra                                                       |
| Test lists groups, but none pass the filter                               | Check **Group Filter**. It is a regular expression matched against the group's display name                                                 |
| Two Entra groups with the same name end up as one Datagrok group          | Groups are matched by display name. Give the groups unique names                                                                             |
| Groups don't sync and Keycloak sync is set up on the server               | Keycloak sync takes over group membership. Entra group sync is skipped while it is on                                                       |
