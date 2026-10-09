---
title: "Report bugs and feature requests"
description: Rules for writing and managing bug reports and feature requests in GitHub Issues.
keywords:
  - github issues
  - github tracker
  - bug report format
  - steps to reproduce
  - issue priority
  - ticket status
---

This guide provides a set of rules for reporting issues and managing
tickets in Datagrok. Everyone, the Datagrok team and customers alike, reports
bugs and feature requests at
[github.com/datagrok-ai/public/issues](https://github.com/datagrok-ai/public/issues).
If the fix turns out to be in the core platform, the team links a tracking issue
to yours, so you don't need to decide where the problem is.

## Reporting an issue

A good ticket has a type, title, and description; the team adds an assignee,
priority, and target date. Larger pieces of work are split into sub-issues of a
parent issue. Here we provide recommendations for each item:

* **Issue type**. Use _Bug_ for unexpected behavior, _Feature_ for a new
  capability or an improvement of existing functionality or UI, and _Task_ for
  other work.
* **Title**. Start the title with the platform module or package name,
  then name unexpected behavior for a bug and a new feature name or improvement summary for an enhancement.

|Issue type|Formula|Example|
|----------|-------|-------|
|Bug| [Platform module] or [Package name] : [Unexpected behavior]| Line chart: Y-axis label is broken|
|Feature| [Platform module] or [Package name] : [New feature name] or [Improvement summary]| Bar Chart: context menu harmonization|

* **Description** is important for testing and writing release notes. For an
enhancement, write the description of the new functionality. A bug description
should include the following items:
  * **Instance and its version**. If the bug concerns a package functionality,
  mention the package version.
  * **Data on which the bug is reproduced (optional)**. If a bug occurs on a
  particular dataset only, include it in the bug description.
  * **Steps to reproduce**. A step-by-step description of your actions causing
  the bug (where to click, what to enter into inputs, which checkboxes to
  mark, etc.)
  * **Expected Result**. Describe how the platform is supposed to work—the ideal
  result you want but don't get.
  * **Actual result**. The result that you receive when using the platform,
  which you don't expect to receive.
  * **Code examples (optional)**. If the bug concerns working with the platform
  API, scripts, queries, or something where you use a code, give an example.
  * **Attachment (optional)**. You are welcome to attach screenshots, GIFs,
  recorded videos, etc. to complete the issue description.
* **Priority**. The team sets the _Priority_ field. Use your common sense above
  all rules described below.
  * _Urgent_. It is a bug in the main functionality of the platform. Such as
  Chem Descriptors, Detectors, and so on.
  * _High_. An important request from the customer, something that blocks
  others' work, or a task with the exact due date. Set the target date for such
  tasks even if it was not initially specified by the issue's reporter. In
  most cases, such requests should be resolved in a week.
  * _Medium_. The default priority for the task.
  * _Low_. A good enhancement for the platform which does not have a big
    impact on the users.
* **Target date**. Set the _Target date_ field according to the priority,
client's request, or corresponding workstream date. Generally, medium-priority
issues should be done within two weeks, high-priority within a week, and
urgent ones within a few days. The release an issue ships in is its milestone.
* **Assignee**. To understand the person responsible for a
particular package, look inside the package.json file, which must exist for
each package. Inside this file, there is an "author" field from which you can
find out whom to assign.
* **Labels (optional)**. Use labels to group related issues.

## Managing tickets

To track the actual state of the platform, it's important to keep tickets up to date:

* Assign the issue to yourself when you start working on it, and comment on
  progress or blockers.
* Link the pull request to the issue with `Closes #123` in its description, so the
  issue closes when the pull request is merged.
* Close an issue that won't be done as _not planned_, or as _duplicate_ with a
  link to the other issue.

>Note: Write meaningful commits, and don't forget to mention the issue number. For details, see the [commit message policy](../dev-process/git-policy.mdx).
