---
title: "Datagrok vs D360 for discovery informatics"
sidebar_label: D360
toc_max_heading_level: 4
mdx:
  format: mdx
description: Compares Datagrok and Certara D360 on architecture, performance, scientific depth, extensibility, AI readiness, licensing, and platform roadmap for drug discovery teams.
keywords:
  - d360 vs datagrok
  - certara d360 alternative
  - d360 alternative
  - design hub alternative
  - discovery informatics platform
  - sar analysis software
  - browser-based cheminformatics
  - drug discovery data analysis
last_update:
  date: November 3, 2026
---

# Datagrok vs D360: Choosing a discovery platform for the next decade

D360 has been a workhorse of discovery informatics for more than a decade. Certara reports that more than 6,000
scientists, from big pharma to small biotech, use it to query discovery data, build SAR, and prioritize compounds. It
does those jobs well, and many organizations have years of query catalogs, dashboards, and habits built around it.

But the ground under D360 is moving. D360 is still a desktop application. Certara has announced a
next-generation platform and has said it intends to unify its products under a single environment, but it has not
published a timeline. For current D360 customers this means a move to a new product, with the migration work that
comes with it. Staying where they are is not a long-term option either.

So the real question for a D360 customer is not whether to change, but what to change to, and when.

Datagrok is the answer that exists today. It was designed recently and specifically for scientific discovery. It runs
entirely in the browser, and its in-memory engine is faster than the D360 desktop client. Chemistry, biology, and assay
data are core parts of the platform. Any part of it can be extended by your own developers. And it all comes under one
simple license.

This article compares the two across architecture, performance, scientific depth, extensibility, AI, and total cost of
ownership.

## The platform question D360 customers already face

D360 consists of a desktop application that talks to the D360 server through a REST layer. Certara itself describes it
as "the D360 desktop application". The architecture has served customers well, but it comes from a time when scientific
software was installed on every scientist's workstation.

Certara's direction is clear from its recent public statements:

* It has announced a **next-generation platform** and said it will let customers use its software products alongside
  frontier AI models, including NVIDIA's BioNeMo agent toolkit.
* It has said it intends to **unify many of its products under a single environment**, and that it has
  **reprioritized its product portfolio and adjusted roadmaps** to accelerate AI.
* It has said it has **not put a timeline** on individual products.

For a D360 customer, a new platform means re-creating query catalogs, dashboards, integrations, and validated
workflows, and retraining users, on a schedule set by the vendor. That work will happen anyway, so it makes sense to
evaluate every option on its merits before it starts.

Datagrok exists today, it runs in production, and you can test it against your own data and workflows now.

## Browser-native, and faster than the desktop

Many people assume that a browser-based tool must be slower than a desktop one. Datagrok shows that this is no longer
true.

At the center of Datagrok is a
[columnar in-memory database built from scratch](../../../develop/under-the-hood/performance.md#in-memory-database)
for exploratory analysis. It stores data in typed arrays, uses high-performance bitsets for filtering and selection,
calculates statistics in a single pass, and parses files on multiple threads without blocking the UI. Viewers render
directly to canvas and WebGL. Heavy algorithms such as
[UMAP and KNN graphs can run on the GPU through WebGPU](../../../explore/dim-reduction.md), up to 100x faster on
large datasets.

As a result, scientists can filter, color, and re-plot millions of rows in real time, and they can do it in a
browser tab. On the operations scientists repeat all day (loading results, filtering, linking views, scrolling a
structure-rich spreadsheet), Datagrok is faster than the D360 desktop client. Teams are encouraged to check this on
their own data.

Running in the browser also brings practical benefits:

* **Nothing to install.** There is no client to package, distribute, and keep in step with the server. Scientists
  open a URL, on Windows, macOS, or Linux.
* **Upgrades happen in one place.** You upgrade the server and plugins once, and every user is on the new version.
  D360 26.5 added a Client Plugins panel so that sketchers and renderers can be updated independently. That is a
  useful improvement, and also a sign of how many parts a desktop client has to maintain on each machine.
* **Sharing is a link.** Projects, dashboards, and applications open the same way for a chemist, a biologist, a
  manager, or an external partner.

## Science-native, not science-configured

In Datagrok, scientific data types are part of the platform itself.
[Semantic types](../../../govern/catalog/semantic-types.md) are detected automatically when data is loaded. A column
of SMILES or molfiles becomes molecules, a column of HELM or FASTA becomes sequences, and a column of fitted curves
becomes dose-response charts in the grid cells. The type determines how values are rendered, how they are searched,
and which tools appear in the context panel. All of this works in any dataset, dashboard, or application, without
setup by IT.

What comes with the platform:

* **Cheminformatics** ([Chem](../../solutions/domains/chem/chem.md)): substructure and similarity search, R-group
  analysis, scaffold tree, activity cliffs, matched molecular pairs, SAR matrix, chemical space,
  [multiparameter optimization](../../solutions/domains/chem/mpo.md), virtual synthesis, Markush enumeration,
  curation, and descriptors and fingerprints
* **Predictive and structural chemistry**: QSAR/QSPR models, ChemProp, ADMET predictions, docking (AutoDock GPU),
  retrosynthesis (AiZynthFinder), generative chemistry (REINVENT4), and structure prediction (Boltz-1, BioNeMo)
* **Biologics and peptides** ([Bio](../../solutions/domains/bio/bio.md)): HELM with non-natural monomers,
  [peptide SAR](../../solutions/domains/bio/peptides-sar.md), MSA, sequence-to-structure conversion with
  [PolyTool](../../solutions/domains/bio/polytool.md), and an [oligonucleotide toolkit](../../solutions/domains/bio/oligo-toolkit.md)
* **Assays**: plate registration and layouts, dose-response fitting with interactive curves, and qPCR
* **Applications**: Hit Design, Hit Triage, and compound registration
* **General data science**: [PCA, UMAP](../../../explore/dim-reduction.md), [clustering](../../../explore/cluster-data.md),
  multivariate analysis, statistical tests, and no-code [machine learning](../../../learn/learn.md)

D360 also offers serious scientific depth. Its SAR tooling includes R-group analysis, matched molecular series, and
activity cliff notifications. It covers biologics, oligonucleotides, and HELM-based peptides, and recent releases added
a peptide design sandbox. The difference is in scope. D360 focuses on querying, visualizing, and analyzing discovery
data. In Datagrok, that analysis is one part of a larger environment that also includes modeling, assay processing,
design and registration applications, and general-purpose statistics. All of it shares the same data model, so a
scientist can go from a question to a model to a shared decision without leaving the workspace.

## One platform instead of a product family

Certara offers discovery informatics as a set of products. D360 (and D360 Express for smaller organizations) handles
data access and analysis. D360 Partner is an add-on for external collaborators. Design Hub manages compound design and
hypotheses. Compound Registration, Compliance Checker, Marvin, and JChem cover registration and core chemistry. These
products integrate well. Design Hub and D360 have been connected for years. But each one is a separate product to
license, deploy, upgrade, and support.

In Datagrok, these capabilities live in one platform:

* **Data access**: [30+ connectors](../../../access/access.md) to databases, files, cloud storage, and web services,
  with visual and SQL query builders. Datagrok also connects to registration and ELN systems such as CDD Vault,
  Benchling, and Revvity Signals.
* **Analysis and visualization**: [high-performance viewers](../../../visualize/viewers/viewers.md) that understand
  chemistry and biology
* **Design and registration**: Hit Design, Hit Triage, and compound registration, built on the same chemistry engine
  and permission model
* **Collaboration**: [shared projects](../../../datagrok/concepts/project/space.md), dashboards, and applications,
  with [fine-grained permissions](../../../collaborate/collaborate.md) for internal teams and external partners

Every capability uses the same identity, permissions, audit trail, and UI conventions. A new capability arrives as a
[plugin](../../../datagrok/plugins.md) installed into the running platform. There is no new product to procure and
stand up.

## Built for developers

Sooner or later every discovery organization needs something the vendor did not build: an internal model, a
proprietary assay format, a project-specific viewer, or a custom triage application. How easy that is determines how
fast the platform can keep up with the science.

**D360** offers REST services and a Python wrapper that give programmatic access to queries and data, and that let
teams push predictions back. This is useful for feeding data into external pipelines. However, the D360 user interface
itself is not open for extension in the same way, so anything beyond data access usually has to be built and hosted
elsewhere.

**Datagrok** treats extensibility as a core design goal:

* **[Functions](../../concepts/functions/functions.md) are first-class.** You can write a script in Python, R, Julia,
  MATLAB, JavaScript, or SQL and annotate its inputs and outputs. The platform then generates a UI for it, runs it at
  scale, applies permissions, records its history, and makes it available in menus, workflows, and to AI.
* **The [full JavaScript API](../../../develop/api-overview.md)** gives access to the same building blocks that
  Datagrok's own plugins use: dataframes, viewers, cell renderers, context panels, events, and applications.
* **[Packages](../../../develop/develop.md)** can add data types, connectors, viewers, and complete applications.
  They are versioned and installed in one click.
* **An open-source codebase.** Most of Datagrok's scientific plugins are published under the MIT license on
  [GitHub](https://github.com/datagrok-ai/public). Your developers can read how the platform's own features are built
  and reuse that code in theirs.
* **Built for AI-assisted development.** The APIs and documentation are structured so that LLMs can understand them,
  so coding assistants can write working Datagrok plugins. Applications that once took months can often be built in
  days.

Consider an internal peptide-scoring model. In Datagrok, a data scientist registers it as a Python function and adds
type annotations. It then shows up as a menu item with a generated form, adds its predictions as a new column next to
the sequences and assay data, and is available in the visual workflow builder and to the AI assistant. No separate
application had to be built, hosted, or maintained.

## AI that works inside the analysis

Certara describes D360's REST services as a way to feed cleansed and aggregated data into AI and ML. At the company
level, it has announced a next-generation AI platform that will integrate NVIDIA BioNeMo agents. It has not said when
or how D360 users will get it.

Datagrok's [AI](../../../explore/ai/ai.md) is available today and works inside the analysis. Everything in Datagrok,
including data, functions, viewers, and UI state, can be inspected in a structured way, so AI can act on the actual
analysis instead of an export:

* **Natural-language analysis**: for example, "Show molecules with IC50 < 10 nM and logP < 3" or "Cluster these
  compounds by similarity"
* **Function chaining**: the assistant turns a request into a sequence of platform functions that can be reviewed
  before it runs
* **MCP in both directions**: Datagrok connects to external MCP servers in a managed way and also exposes its own MCP
  server for outside agents
* **Governance by design**: AI goes through the same functions and permissions as the user, so its results can be
  inspected and reproduced

## Simpler licensing, lower total cost of ownership

The cost of discovery software goes well beyond the license. It includes every client to install, every integration
to maintain, and every product boundary that users and IT have to work around.

**D360** TCO includes:

* A desktop client installed and maintained on every scientist's workstation
* Separate products and add-ons for analysis, partner access, design, registration, and core chemistry, each with
  its own license and upgrade cycle
* Custom applications and data science workflows built and hosted outside the platform
* A future migration to Certara's next-generation platform, on Certara's timeline

**Datagrok** TCO includes:

* One platform under one simple license
* Nothing to install on the desktop; users connect through a browser
* [Lightweight deployment](../../../deploy/deploy.md) with Docker or Kubernetes, on premises or in the cloud, or with
  one click from the [AWS Marketplace](../../../deploy/aws/deploy-marketplace.md)
* Fast in-browser computation, which reduces the load on servers
* Custom capabilities built as plugins that run inside the platform
* One consistent interface for chemists, biologists, data scientists, and partners

## Migrating without a big bang

Moving off D360 does not have to happen all at once. Datagrok can connect to the same discovery databases that D360
queries, as well as registration systems, ELNs, and file stores. It can also call D360's REST services. Teams can start
with a single project or workflow, run both systems side by side, and move further once the value is proven.

## When to choose which

**Choose D360 when:**

* Your current deployment, query catalog, and validated workflows are deeply embedded, and you are prepared to
  migrate when Certara's next-generation platform arrives
* Your design and registration workflows depend on Design Hub and the wider Chemaxon stack
* Your needs mostly involve standard query, SAR, and reporting, with little demand for custom applications or models

**Choose Datagrok when:**

* You would rather make the platform decision now than wait for a vendor-driven migration
* You want speed and zero install: a browser-based platform that is faster than the desktop tool it replaces
* Chemistry, biologics, assays, and general data science need to work together in one system
* Your teams build their own models, viewers, or applications, and want them to run inside the platform
* AI-assisted analysis and development are strategic priorities
* Reducing the number of tools, licenses, and the IT footprint matters

## Capability comparison

|                                | **D360**                                                                                                   | **Datagrok**                                                                                                                                       |
|:-------------------------------|:-----------------------------------------------------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------|
| **Core identity**              | Discovery data query, analysis, and visualization application                                              | Scientific platform for exploration, modeling, and fit-for-purpose R&D applications                                                                |
| **Architecture**               | Desktop application communicating with a server through REST                                               | Browser-native in-memory data engine with server-side compute                                                                                      |
| **Roadmap**                    | Next-generation platform announced, with no published timeline                                             | Available today; continuous releases on the same platform                                                                                          |
| **Performance**                | Desktop client                                                                                             | In-memory columnar engine, canvas and WebGL viewers, WebGPU acceleration; faster than the D360 desktop client                                      |
| **Client footprint**           | Installed client on every workstation                                                                      | None; any modern browser                                                                                                                           |
| **Data access**                | Self-service drag-and-drop queries over a configured data catalog                                          | 30+ connectors, visual and SQL query builders, files, and web services                                                                             |
| **Cheminformatics and SAR**    | R-groups, matched molecular series, activity cliffs, MPO, virtual compounds                                | R-groups, scaffold tree, activity cliffs, MMP, SAR matrix, MPO, chemical space, enumeration, curation                                              |
| **Biologics and peptides**     | HELM, peptides, oligos, antibodies, ADCs; peptide design sandbox                                           | HELM, peptide SAR, MSA, PolyTool sequence-to-structure, oligo toolkit                                                                              |
| **Modeling and ML**            | Predictions are typically produced externally and pushed in through APIs                                   | Built-in ML, ChemProp, ADMET, docking, retrosynthesis, REINVENT4, Boltz-1; Python, R, Julia, and MATLAB scripts                                     |
| **Design and registration**    | Separate products (Design Hub, Compound Registration)                                                      | Hit Design, Hit Triage, and compound registration on the same platform                                                                             |
| **Extensibility**              | REST services and a Python wrapper for data access                                                          | [Functions](../../concepts/functions/functions.md) in any language, full JS API, plugins that add types, viewers, and apps; open-source plugin code |
| **AI**                         | REST services supply data to external AI/ML; company-level AI platform announced                            | Assistant built into the analysis, function chaining, MCP client and server, governed by platform permissions                                      |
| **External collaboration**     | D360 Partner add-on                                                                                        | Built-in sharing with fine-grained permissions                                                                                                     |
| **Deployment**                 | Server plus desktop clients                                                                                | Docker or Kubernetes, on premises or cloud, or AWS Marketplace                                                                                     |
| **Licensing**                  | Product family with editions and add-ons                                                                   | One platform, one simple license                                                                                                                   |
| **Best suited for**            | Organizations staying on an established D360 deployment                                                    | Teams that want a fast, modern, extensible, AI-ready discovery platform today                                                                      |
