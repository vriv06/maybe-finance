# Canvas edits vs. design-lead rev 2

Source: canvas https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT (version 1791500804-f0ee). Baseline: rev 2 mockup HTML split per screen (incl. Victor's 'Last on' edits). Lines starting `-` = rev 2, `+` = canvas now.

## Budget.dc.html

```diff
@@ -87,2 +87,15 @@
 <!-- DS::Alert :warning -->
+<h3 class="text-sm text-secondary flex items-center gap-1.5">
+<svg repeat/>
+<span>Recurring payments</span>
+</h3>
+<p class="tabular-nums">
+<span class="block text-xl font-medium text-primary">$6,551.00</span>
+<span class="block text-sm text-secondary">committed to recurring payments</span>
+</p>
+<div class="flex h-1.5 gap-1">
+<div class="rounded-md h-1.5 bg-inverse" style="width: 100%; background-color: #ed4e4e">
+</div>
+</div>
+<p class="text-sm text-primary font-medium tabular-nums">123% of your budget</p>
 <div class="flex items-start gap-3 p-4 rounded-lg border bg-alert-warning text-alert-warning border-alert-warning" data-alert="">
@@ -91,4 +104,2 @@
 <p class="font-medium text-pretty tabular-nums">Recurring payments are $1,700.00 over your December 2026 budget</p>
-<p class="text-secondary mt-1 tabular-nums">$9,200.00 committed, 123% of the $7,500.00 budgeted for spending.</p>
-<p class="text-secondary mt-1">Compared with your October 2026 budget. Set up December 2026 to use its own.</p>
 <a href="#" class="btn btn-sm btn-outline mt-3" aria-label="Review December 2026 budget">Review budget</a>
@@ -99,39 +110,2 @@
 <span class="font-medium text-sm text-primary">See details</span>
-</div>
-</div>
-</figure>
-<figure class="space-y-2 col-300" data-check="c4-own">
-<figcaption class="chrome-label">3 · OVER ITS OWN BUDGET (NO REFERENCE LINE)</figcaption>
-<div class="bg-container rounded-xl shadow-border-xs p-4 space-y-3">
-<div class="flex items-start gap-3 p-4 rounded-lg border bg-alert-warning text-alert-warning border-alert-warning" data-alert="">
-<svg triangle-alert/>
-<div class="flex-1 text-sm min-w-0">
-<p class="font-medium text-pretty tabular-nums">Recurring payments are $200.00 over your February 2027 budget</p>
-<p class="text-secondary mt-1 tabular-nums">$9,200.00 committed, 103% of the $9,000.00 budgeted for spending.</p>
-<a href="#" class="btn btn-sm btn-outline mt-3" aria-label="Review February 2027 budget">Review budget</a>
-</div>
-</div>
-<div class="px-3 py-2 rounded-xl flex items-center gap-3 bg-surface">
-<svg chevron-right/>
-<span class="font-medium text-sm text-primary">See details</span>
-</div>
-</div>
-</figure>
-<figure class="space-y-2 col-300" data-check="c4-stress">
-<figcaption class="chrome-label">4 · STRESS · 7 DIGITS + "SEPTEMBER 2027" · NO TRUNCATION</figcaption>
-<div class="bg-container rounded-xl shadow-border-xs p-4 space-y-3">
-<div class="flex items-start gap-3 p-4 rounded-lg border bg-alert-warning text-alert-warning border-alert-warning" data-alert="">
-<svg triangle-alert/>
-<div class="flex-1 text-sm min-w-0">
-<p class="font-medium text-pretty tabular-nums">Recurring payments are $1,234,567.89 over your September 2027 budget</p>
-<p class="text-secondary mt-1 tabular-nums">$2,734,567.89 committed, 183% of the $1,500,000.00 budgeted for spending.</p>
-<a href="#" class="btn btn-sm btn-outline mt-3">Review budget</a>
-</div>
-</div>
-<div>
-<p class="chrome-label mb-1">NEUTRAL WITH 7 DIGITS</p>
-<p class="tabular-nums">
-<span class="block text-xl font-medium text-primary">$1,234,567.89</span>
-<span class="block text-sm text-secondary">committed to recurring payments</span>
-</p>
 </div>
```

## Card.dc.html

```diff
@@ -34,12 +34,2 @@
 </dl>
-<!-- DS::Alert variant: :warning (message composed) -->
-<div class="flex items-start gap-3 p-4 rounded-lg border bg-alert-warning text-alert-warning border-alert-warning" data-alert="">
-<svg triangle-alert/>
-<div class="flex-1 text-sm min-w-0">
-<p class="font-medium text-pretty">2 upcoming budgets are over. The first is November 2026.</p>
-<p class="text-secondary mt-1 tabular-nums">Across all accounts: $9,200.00 committed, 123% of the $7,500.00 budgeted for spending.</p>
-<p class="text-secondary mt-1">Compared with your October 2026 budget. Set up November 2026 to use its own.</p>
-<a href="#" class="btn btn-sm btn-outline mt-3" aria-label="Review November 2026 budget">Review budget</a>
-</div>
-</div>
 <section class="space-y-3" aria-labelledby="upc">
@@ -143,3 +133,2 @@
 </div>
-<p class="chrome-label">… CONTINUES THROUGH DEC 27 (CURRENT + 2 BUDGET MONTHS)</p>
 <a href="#future" class="btn btn-outline w-full" aria-label="See later months in your budget">See later months <svg arrow-right/>
```

## Convert.dc.html

```diff
@@ -23,5 +23,8 @@
 <div class="flex items-center justify-between gap-4 p-3">
-<h4 class="text-sm text-primary">Recurring payment</h4>
-<button class="btn btn-outline" aria-label="Set up recurring payment">
-<svg repeat/>Set up</button>
+<div class="text-sm space-y-1">
+<h4 class="text-primary">Recurring payment</h4>
+<p class="text-secondary">One time</p>
+</div>
+<button class="btn btn-outline" aria-label="Edit recurring payment">
+<svg pencil/>Edit</button>
 </div>
@@ -32,3 +35,3 @@
 </div>
-<span class="w-9 h-5 rounded-full bg-surface-inset border border-secondary shrink-0" style="width: 23px; border-radius: 24px">
+<span class="w-9 h-5 rounded-full bg-surface-inset border border-secondary shrink-0" style="width: 23px; border-radius: 6px; height: 23px">
 </span>
@@ -121,3 +124,3 @@
 <div class="mt-3 rounded-lg border border-tertiary p-3 space-y-3">
-<h4 tabindex="-1" class="text-sm font-medium text-primary tabular-nums rounded" style="outline:2px solid var(--text-primary);outline-offset:2px">Split $26,100.00 into 18 installments</h4>
+<h4 tabindex="-1" class="text-sm font-medium text-primary tabular-nums rounded">Split $26,100.00 into 18 installments</h4>
 <ul class="list-disc pl-5 space-y-1 text-sm text-secondary tabular-nums">
```

## Dialogs.dc.html

```diff
@@ -98,3 +98,3 @@
 <div class="flex flex-col gap-2">
-<button class="btn btn-destructive w-full">Delete purchase and installments</button>
+<button class="btn btn-destructive w-full">Delete</button>
 <button class="btn btn-outline w-full">Keep it</button>
```

## Future.dc.html

```diff
@@ -315,3 +315,3 @@
 <h4 class="text-primary">Start from your October 2026 budget</h4>
-<p class="text-secondary">Copies October 2026's income, spending, and category amounts as a starting point. You can adjust anything after.</p>
+<p class="text-secondary">Copies October 2026's budget</p>
 </div>
```

## Main.dc.html

```diff
@@ -120,2 +120,69 @@
 </div>
+<div class="rounded-lg border border-tertiary" style="padding:12px;display:flex;flex-direction:column;gap:12px" data-impact="">
+<div class="flex items-start" style="gap:8px">
+<svg triangle-alert/>
+<div class="text-sm tabular-nums" style="min-width:0">
+<p class="font-medium text-destructive">This puts November 2026 $301.00 over budget</p>
+<p class="text-secondary">Budget impact of the next 3 installments</p>
+</div>
+</div>
+<ul style="display:flex;flex-direction:column;gap:12px;margin:0;padding:0;list-style:none">
+<li style="display:flex;flex-direction:column;gap:6px">
+<div class="flex items-center justify-between text-sm tabular-nums">
+<span class="text-primary font-medium">November 2026</span>
+<span class="text-destructive font-medium">$301.00 over</span>
+</div>
+<div class="bg-surface-inset" style="position:relative;display:flex;height:8px;border-radius:4px">
+<div class="bg-inverse" style="width:72.8%;height:8px;border-radius:4px 0 0 4px">
+</div>
+<div style="width:13.9%;height:8px;background-color:#EC2222;border-radius:0 4px 4px 0">
+</div>
+<div style="position:absolute;left:83.3%;top:-4px;width:2px;height:16px;background-color:#737373;border-radius:1px" aria-hidden="true">
+</div>
+</div>
+<p class="text-xs text-secondary tabular-nums">$7,801.00 of $7,500.00 budgeted</p>
+</li>
+<li style="display:flex;flex-direction:column;gap:6px">
+<div class="flex items-center justify-between text-sm tabular-nums">
+<span class="text-primary font-medium">December 2026</span>
+<span class="text-secondary">98% of budget</span>
+</div>
+<div class="bg-surface-inset" style="position:relative;display:flex;height:8px;border-radius:4px">
+<div class="bg-inverse" style="width:67.8%;height:8px;border-radius:4px 0 0 4px">
+</div>
+<div style="width:13.9%;height:8px;background-color:#EC2222;border-radius:0 4px 4px 0">
+</div>
+<div style="position:absolute;left:83.3%;top:-4px;width:2px;height:16px;background-color:#737373;border-radius:1px" aria-hidden="true">
+</div>
+</div>
+<p class="text-xs text-secondary tabular-nums">$7,350.00 of $7,500.00 budgeted</p>
+</li>
+<li style="display:flex;flex-direction:column;gap:6px">
+<div class="flex items-center justify-between text-sm tabular-nums">
+<span class="text-primary font-medium">January 2027</span>
+<span class="text-secondary">95% of budget</span>
+</div>
+<div class="bg-surface-inset" style="position:relative;display:flex;height:8px;border-radius:4px">
+<div class="bg-inverse" style="width:65.6%;height:8px;border-radius:4px 0 0 4px">
+</div>
+<div style="width:13.9%;height:8px;background-color:#EC2222;border-radius:0 4px 4px 0">
+</div>
+<div style="position:absolute;left:83.3%;top:-4px;width:2px;height:16px;background-color:#737373;border-radius:1px" aria-hidden="true">
+</div>
+</div>
+<p class="text-xs text-secondary tabular-nums">$7,150.00 of $7,500.00 budgeted</p>
+</li>
+</ul>
+<div class="flex items-center text-xs text-secondary" style="gap:16px">
+<span class="flex items-center" style="gap:6px">
+<span class="bg-inverse" style="display:inline-block;width:8px;height:8px;border-radius:2px">
+</span>Already committed</span>
+<span class="flex items-center" style="gap:6px">
+<span style="display:inline-block;width:8px;height:8px;border-radius:2px;background-color:#EC2222">
+</span>This purchase</span>
+<span class="flex items-center" style="gap:6px">
+<span style="display:inline-block;width:2px;height:10px;background-color:#737373">
+</span>Budget</span>
+</div>
+</div>
 </div>
```

## Rows.dc.html

```diff
@@ -26,8 +26,4 @@
 <svg credit-card/>
-<span class="min-w-0">Installment 1 of 12 <span aria-hidden="true">·</span>
-<a href="#" class="text-primary font-medium hover:underline whitespace-nowrap" aria-label="View plan for MacBook Air">View plan</a>
-<span class="hidden lg:inline">
-<span aria-hidden="true">·</span>
-</span>
-<a href="#" class="hidden lg:inline hover:underline">BBVA Azul</a>
+<span class="min-w-0">
+<a href="https://05835fe7-1cce-41d7-a40e-66958a882d0c.frame.claudeusercontent.com/appifact/Rows.dc.html#" class="hidden lg:inline hover:underline" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">BBVA Azul</a>&nbsp;&nbsp;<span aria-hidden="true" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">·</span> Installment 1 of 12&nbsp;<a href="#" class="text-primary font-medium hover:underline whitespace-nowrap" aria-label="View plan for MacBook Air">View plan</a>
 </span>
@@ -76,8 +72,6 @@
 <svg repeat/>
-<span class="min-w-0">Monthly charge <span aria-hidden="true">·</span>
-<a href="#" class="text-primary font-medium hover:underline">View plan</a>
-<span class="hidden lg:inline">
-<span aria-hidden="true">·</span>
-</span>
-<a href="#" class="hidden lg:inline hover:underline">BBVA Azul</a>
+<span class="min-w-0">
+<span class="hidden lg:inline" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">
+</span>
+<a href="https://05835fe7-1cce-41d7-a40e-66958a882d0c.frame.claudeusercontent.com/appifact/Rows.dc.html#" class="hidden lg:inline hover:underline" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">BBVA Azul</a>&nbsp;&nbsp;<span aria-hidden="true" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">·</span> Monthly charge&nbsp;<a href="#" class="text-primary font-medium hover:underline">View plan</a>
 </span>
@@ -108,8 +102,6 @@
 <svg credit-card/>
-<span class="min-w-0">Paid in 12 installments <span aria-hidden="true">·</span>
+<span class="min-w-0">
+<a href="https://05835fe7-1cce-41d7-a40e-66958a882d0c.frame.claudeusercontent.com/appifact/Rows.dc.html#" class="hidden lg:inline hover:underline" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">BBVA Azul</a>&nbsp;<span aria-hidden="true" style="--tw-border-spacing-y: 0; --tw-translate-x: 0; --tw-translate-y: 0; --tw-rotate: 0; --tw-skew-x: 0; --tw-skew-y: 0; --tw-scale-x: 1; --tw-scale-y: 1; --tw-scroll-snap-strictness: proximity; --tw-ring-offset-width: 0px; --tw-ring-offset-color: #fff; --tw-ring-color: rgb(59 130 246 / 0.5); --tw-ring-offset-shadow: 0 0 #0000; --tw-ring-shadow: 0 0 #0000; --tw-shadow: 0 0 #0000; --tw-shadow-colored: 0 0 #0000">·</span> Paid in 12 installments <span aria-hidden="true">·</span>
 <a href="#" class="text-primary font-medium hover:underline">View plan</a>
-<span class="hidden lg:inline">
-<span aria-hidden="true">·</span>
-</span>
-<a href="#" class="hidden lg:inline hover:underline">BBVA Azul</a>
+<span class="hidden lg:inline">&nbsp;</span>
 </span>
@@ -138,9 +130,8 @@
 </header>
-<div tabindex="-1" class="flex items-start gap-3 rounded-lg border border-tertiary p-3">
-<svg credit-card/>
-<div class="text-sm space-y-3 min-w-0">
+<div tabindex="-1" class="flex items-start gap-3 rounded-lg border border-tertiary p-3" style="justify-content: space-between; align-items: center">
+<div style="box-sizing: border-box; display: flex; flex-direction: row; gap: 12px; align-items: center">
+<svg credit-card/>
 <p class="text-primary font-medium">Installment 1 of 12</p>
-<p class="text-secondary -mt-2">Counts as spending. Doesn't change your card balance.</p>
+</div>
 <a href="#c3" class="btn btn-sm btn-outline" aria-label="View plan for MacBook Air">View plan</a>
-</div>
 </div>
@@ -156,4 +147,4 @@
 <div class="flex flex-col gap-1">
-<div class="flex gap-2" data-pair="">
-<label class="form-field w-1/3">
+<div class="flex gap-2" data-pair="" style="flex-direction: column">
+<label class="form-field w-1/3" style="width: 100%">
 <span class="form-field__label">Type</span>
@@ -161,3 +152,3 @@
 </label>
-<label class="form-field w-2/3">
+<label class="form-field w-2/3" style="width: 100%">
 <span class="form-field__label">Amount</span>
```

