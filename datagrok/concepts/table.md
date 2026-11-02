---
title: "Dataframe"
sidebar_position: 1
description: Describes the dataframe (table) structure in Datagrok, its columns, metadata, and how to filter and search tables.
keywords:
  - table structure
  - column properties
  - column tags
  - semantic type
  - table metadata
  - smart search fields
  - grid viewer
---

A table (also known as a dataframe) is a two-dimensional structure with named columns of different types. Supported types
are: `string`, `bool`, `int`, `bigint`, `double`, `qnum`, `datetime`.

Dataframes are visualized using the [grid](../../visualize/viewers/grid.md) viewer.

## Column

Dataframes consist of columns. In addition to the data type, a column can be
associated with [tags](../../govern/catalog/tags.md) that specify units, data
format, [semantic type](../../govern/catalog/semantic-types.md), tooltip content
and so forth. 

To view column properties, right-click a column header and select
**Properties...** The [Context Panel](../navigation/panels/panels.md#context-panel) updates to show the column's properties.
To edit the column's name and tags, right-click the column header and select **Column Properties...**, or press <kbd>F2</kbd>.

## Metadata

Like columns, each table can be annotated with attributes in the form of
key-value pairs. Datagrok automatically annotates certain tables with metadata
(such as the source of the table, or time of import, etc). Table metadata is
shown in the **General** pane of the
[Context Panel](../navigation/panels/panels.md#context-panel), and can be changed
through the JS API (`df.tags`).

## Filtering

You can use these fields to filter tables with smart search:

| Field       | Description                      |
|-------------|----------------------------------|
| ID          |                                  |
| name        |                                  |
| rowCount    |                                  |
| colCount    |                                  |
| createdOn   |                                  |
| updatedOn   |                                  |
| author      | [User](../../govern/access-control/users-and-groups#users) object |
| starredBy   | [User](../../govern/access-control/users-and-groups#users) object |
| commentedBy | [User](../../govern/access-control/users-and-groups#users) object |

See also:

* [JS API: Dataframe](https://datagrok.ai/api/js/dg/classes/DataFrame)
* [Space](project/space.md)
* [Dashboard](project/dashboard.md)
* [Table view](../../visualize/table-view-1.md)
* [View layout](../../visualize/view-layout.md)
* [Tags](../../govern/catalog/tags.md)
* [Grid](../../visualize/viewers/grid.md)
