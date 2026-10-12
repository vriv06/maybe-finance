# Taste Profile: Pagos recurrentes y MSI

_Calibrated 2026-10-08 with Victor (creative director)._

## Existing Design System

Maybe's design system (`app/assets/tailwind/maybe-design-system.css` + `app/components/DS/`) already sets most of the taste. This feature lives inside it and adds no new tokens or components.

### Taste Signals from the System
- **Colour philosophy:** roughly 90% neutral grays (`gray-25`…`gray-900`, functional tokens `text-primary`, `bg-container`, `border-primary`). Colour is semantic only: `text-success` / `text-destructive` for money in and out, and `text-warning` (yellow-400) for attention. Yellow tints (`yellow-tint-5` / `-10`) exist for soft backgrounds.
- **Density:** balanced. Lists are compact rows inside `bg-container` cards with `rounded-xl`, and inputs use `rounded-md` / `rounded-lg`.
- **Personality:** soft radii (8px / 10px) and almost invisible shadows (6% black). The system is approachable, quiet and precise.
- **Typography voice:** Geist for the UI and Geist Mono available for figures. The tone is functional and contemporary, not decorative.
- **Components available:** `DS::Disclosure`, `DS::Tabs`, `DS::Dialog`, `DS::Toggle`, `DS::Tooltip`, `DS::Alert`, `DS::FilledIcon`, `DS::Menu`, `DS::Button` / `DS::Link`.

### Where the User Wants to Evolve
Victor wants **useful alerting**: commitments should stand out enough to stop him from taking on more MSI than he can pay. This has to happen without leaving the quiet system. The tension is resolved with emphasis and copy, not with new colour: see principle 2.

## Emotional Target
**Useful alert.** When Victor opens a card or his budget, he should see right away how much is already committed in the coming months and feel that the number is a real limit. The tone is like a financial copilot giving a clear warning: direct, no drama and no noise. Capture still has to feel fast and certain, because the system does the arithmetic.

## Aesthetic Principles

1. **The number is the alert.** The commitment figure (for example "$4,850 committed / month" or "$18,200 left on MSI") carries the emphasis through size, weight and position, not through badges or colour blocks.
   _Test: if you remove all colour, can you still tell which number matters most?_

2. **Warning colour is rare and earned.** `text-warning` / `yellow-tint-*` appear only when there is a reason to warn, for example when monthly commitments exceed a threshold or the budget. Plain debt that is already planned stays neutral. Every warning carries text plus an icon, never colour alone.
   _Test: in a normal state, is there zero yellow on screen? When there is yellow, is there a sentence explaining why?_

3. **Indistinguishable from Maybe.** Every new field, row or line uses existing DS components and patterns, such as the icon boxes from the budget setup or the transaction lists. A reviewer should not be able to tell which screen is new.
   _Test: put a screenshot of the new screen next to an existing one. Do spacing, radius, type and states match?_

4. **One field, not a flow.** Turning a purchase into MSI is a field inside the form (`DS::Disclosure`), not a separate screen or wizard. Derived values (instalment amount, end date, payments left) appear inline and are announced.
   _Test: can a past purchase be captured or converted without leaving the current screen?_

5. **Generated, explained.** Rows the system creates say so in plain words ("Installment 2 of 6") with an icon and a link to the rule. They look like normal transactions, plus a light provenance mark.
   _Test: can someone tell without hovering why a row exists and where it comes from?_

## Quality Level
**Flagship.** Every state is designed and polished:
- Empty, loading, error, completed and cancelled states.
- `aria-live` announcements for derived values.
- Figures in tabular numerals (Geist Mono or `tabular-nums`) so columns line up.
- Hover and focus states consistent with DS components.
- Subtle transitions when a derived value recalculates, with `prefers-reduced-motion` respected.
- Copy reviewed for reading level.

There are no new components: flagship comes from finish, not from new pieces.

## References
| Reference | What to borrow | What to avoid |
|-----------|---------------|---------------|
| **Maybe (existing screens)**: budget setup icon boxes, account card tabs, transaction lists and drawer | Spacing, radius, card structure, list row anatomy, `DS::Disclosure` for optional sections, tabs on the account card | Nothing. This is the baseline |
| **Dime "Upcoming"** | An upcoming-payments list grouped by date, each row showing amount + name + "x of n" remaining, with a clear total for the period | Its iOS look (cards, colours, gradients). Borrow the information structure, not the skin |

## Anti-References
| Anti-reference | What makes it wrong for us |
|----------------|---------------------------|
| **Noisy dashboard** | Charts, badges and colours used to explain a single number. The alert must come from the figure, not from decoration |
| **Multi-step wizard** | Separate screens to set up something that is one field on the form, which breaks principle 4 |
| **Traditional banking** | Dense tables and jargon such as "diferimiento" or "cargo recurrente programado". We use everyday language |

## Craft Standards
- **Shadows:** the system ones (`shadow-xs` / `shadow-sm`, 6%). No new depth.
- **Borders:** `border-primary` / `border-secondary`. Use dividers between rows, as in transaction lists.
- **Radius:** `rounded-md` for inputs, `rounded-lg` for chips and inner blocks, `rounded-xl` for container cards.
- **Colour usage:**
  - Neutral by default.
  - `text-success` / `text-destructive` only for amounts, as Maybe already does.
  - `text-warning` + `yellow-tint-5/10` only for warnings, and always with text and an icon.
  - No brand colours, gradients or decorative fills.
- **Typography:** Geist. Key figures `text-primary` with stronger weight and size. Amounts in rows use `tabular-nums` to keep alignment. Secondary text uses `text-secondary` / `text-subdued`.
- **Whitespace:** balanced, same as current lists. Commitments get more air than the rows around them, so they work as a focal point.
- **Animation:** minimal and quick (≤150 ms), only to confirm recalculations or expand the disclosure. Turn it off with `prefers-reduced-motion`.
- **Icons:** the `icon` helper only, never `lucide_icon` directly. Proposals:
  - `repeat` for recurring payments and plans.
  - `calendar-clock` for upcoming payments.
  - `alert-triangle` for warnings.
  - `credit-card` for MSI.

## Personality
A good financial copilot. Dresses simply, speaks little and precisely ("You have $4,850 committed per month until March"), and raises their voice only when needed, then says exactly why. Never scolds and never uses jargon.

## Tensions to resolve (for content-writer / design-lead)
- **Useful alert vs. principle 2 (rare warning colour):** what threshold triggers the warning? Options:
  - commitments > X% of the monthly budget;
  - commitments in a month > the budget's available amount;
  - a manual threshold.
  The design-lead should propose one and Victor should decide.
- **Flagship vs. reusing components:** polish has to fit inside the existing components (states, copy, `aria-live`, tabular numbers). If a flagship detail needs a new component, escalate it before building.
