---
title: "Custom function view"
sidebar_position: 2
description: Build your own view for a model in code and keep Compute2's saving and opening of runs.
keywords:
  - custom function view
  - CustomFunctionView
  - model view in code
  - run history
---

When the [Rich Function View](rich-function-view.md) form doesn't fit a model, you can write the view
yourself. A custom function view is a view class in your package that shows the model's inputs and
results the way you build them. The whole view is yours. Compute2 adds **Save** and
**Open a saved run** buttons to its top panel, which work with **My runs** and spaces.

## Creating a view

Extend `CustomFunctionView` from `@datagrok-libraries/compute-api` and pass the qualified name of the
model function to the constructor. The view prepares a call of that function with its default input
values, available as `funcCall`. Implement two methods:

* `buildIO()` returns the view content. It's called when the view opens, with `funcCall` ready.
* `onAfterLoadRun(run)` shows a run that was opened. `funcCall` is already the opened run.

Then register a function that returns the view, with `Compute2:CustomFunctionViewEditor` as its editor.
Opening this function opens the view.

```typescript
import * as ui from 'datagrok-api/ui';
import * as DG from 'datagrok-api/dg';
import {CustomFunctionView} from '@datagrok-libraries/compute-api';

class DayView extends CustomFunctionView {
  private volume?: DG.InputBase;
  private result = ui.divText('');

  constructor() {
    super('MyPackage:DayCalculation');
  }

  buildIO() {
    this.volume = ui.input.float('Incoming volume', {
      value: this.funcCall!.inputs['incomingVolume'],
      onValueChanged: (value) => this.funcCall!.inputs['incomingVolume'] = value,
    });
    return ui.divV([this.volume, ui.bigButton('Run', async () => {
      await this.funcCall!.call();
      this.result.textContent = `Final volume: ${this.funcCall!.outputs['finalVolume']}`;
    }), this.result]);
  }

  async onAfterLoadRun(run: DG.FuncCall) {
    this.volume!.value = run.inputs['incomingVolume'];
    this.result.textContent = `Final volume: ${run.outputs['finalVolume']}`;
  }
}

//name: Day view
//editor: Compute2:CustomFunctionViewEditor
//output: object view
export function dayView() {
  return new DayView();
}
```

## Saving and opening runs

* <i class="fas fa-save"></i> **Save** opens the **Save run** dialog for the current call: pick
  **My runs** or a space, then enter a name, description, and tags. Names work as in the
  [Rich Function View](rich-function-view.md#save-a-run).
* <i class="fas fa-history"></i> **Open a saved run** opens the **Open run** dialog: pick **My runs** or a
  space and a run of the model, then click **Open**. The view shows it through `onAfterLoadRun`.

When the view's function is in the **Model Hub**, **Tools** > **Browse Runs...** lists the runs saved
from the view under it, and opens them in the view again.

Two optional methods run around each save: `onBeforeSaveRun(call)` gets the copy that is about to be
saved, and `onAfterSaveRun(run)` gets the saved run.

To save or open from your own controls, call `saveRunWithDialog(this.funcCall!)` or
`openRunWithDialog()`. To save without the dialog, call `saveRun(call)`, and to open a run by its id,
`loadRun(id)`. Both run the same hooks.

## Exporting runs

To let users download the current run, set `exports` to a list of named exports. Each export returns
the file as a `DG.FileInfo`, which is downloaded under its own name. The
<i class="fas fa-arrow-to-bottom"></i> **Export** icon runs the first export, and **Model** > **Export**
lists them all.

```typescript
exports = [
  {name: 'Result as CSV', export: async () => DG.FileInfo.fromString('result.csv', this.resultCsv())},
];
```

When the current run can't be exported yet, for example before it ran, set `exportEnabled` to `false`.
This greys out the icon and the menu items until you set it back to `true`.

## Adding ribbon items

The view builds its ribbon after `buildIO()` and rebuilds the panels when Compute2 adds **Save** and
**Open a saved run**, so items added in `buildIO()` are lost. Override `buildRibbonPanels()` and
`buildRibbonMenu()` instead, and call `super` first:

```typescript
buildRibbonPanels() {
  const panels = [...super.buildRibbonPanels(), [ui.iconFA('eraser', () => this.result.textContent = '')]];
  this.setRibbonPanels(panels);
  return panels;
}

buildRibbonMenu() {
  super.buildRibbonMenu();
  this.ribbonMenu.group('Day').item('Clear result', () => this.result.textContent = '');
}
```

## Without Compute2's editor

The **Save** and **Open a saved run** buttons come from Compute2's editor, and so does opening the run
from a link to it. A view opened another way has no buttons, ignores the link, and `saveRunWithDialog`
and `openRunWithDialog` do nothing. To give such a view your own
dialogs, set its `runStorage` to an object with `saveDialog(call)` and `openDialog(func)` functions.
