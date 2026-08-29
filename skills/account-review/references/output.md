# Review output

## Structure

**Header.** Account, buildings, services under contract, contract term and renewal
date, date of review, who prepared it.

**Bottom line.** Three to five sentences. What is overdue, what the biggest
opportunity is, whether the account is at risk. Written so it can be read alone.

**Status.** One line each: Retention status, open deficiency count and oldest,
count of overdue cycle items, total identified opportunity band.

**Cycle table.** From `references/cycles.md`. System, item, last performed, next
due, status. Anything with no record flagged separately.

**Open deficiencies.** Aged, sorted oldest first. What it is, found date, severity,
quoted yes or no, last customer response.

**Opportunities.** Tiered Now / This quarter / Watch. Each with trigger, work,
value band, and the specific next action with a name attached.

**Retention.** Status, the signals behind it, and what to do if it is Watch or
At Risk.

**Data gaps.** What was missing and how it limits the review. Never omit this
section, even when it is empty. Write "none" instead.

## Rules

Plain status words: Current, Due, Overdue, Stable, Watch, At Risk. Never emoji.

Every number traces to source data. Where a number is an estimate, label it and
say what it is based on.

Ranges for money, not false precision. Exact figures come from
`fire-inspection-quote`, and if a figure came from the engine, say so.

Next actions are specific and assigned. A named contact and a concrete verb.

Sort by what to do first, not by system type. The review is a work order, not a
report card.

## Voice

Internal analysis is plain and direct, no voice skill needed.

Anything meant to reach the customer, a renewal note, a deficiency follow-up
email, a QBR summary they will read, goes through `shawn-voice`. Do not blend the
two in one document. Keep customer-facing language in its own clearly marked
section so it can be lifted out.

## Formats

Markdown by default. `docx` or `pdf` when Shawn needs to hand it over. `xlsx` for
portfolio views across many accounts, where the cycle table is the useful artifact
and one sheet per account beats one document per account.
