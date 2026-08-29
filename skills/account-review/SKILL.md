---
name: account-review
description: Review a fire life safety inspection account for expansion revenue and retention risk. Use when Shawn says "review this account", "what are we missing at [customer]", asks what work is due or overdue at a property, wants to find repair or added-service revenue in existing customers, or is preparing for a renewal or QBR.
---

# Account review

Sobieski's growth is mostly inside accounts it already has. A recurring inspection
customer generates work every year whether or not anyone asks for it, and the
largest single leak in this business is deficiencies that got found, quoted, and
then never followed up.

This skill reviews one account, or a portfolio, and produces a written review that
says what is due, what is open, what is at risk, and what to do about it in order.

## What this skill will not do

**It will not invent data.** Not a due date, not a deficiency count, not a dollar
figure. If the inspection history is not in front of you, say what is missing and
ask for it. Reviews built on plausible-looking guesses are worse than no review,
because they get acted on.

**It will not price anything.** Pricing goes through `fire-inspection-quote` and
its engine. This skill sizes opportunities in ranges and flags what needs a real
quote. If a number needs to be exact, run the engine.

## Inputs

Ask for whatever exists:

- Inspection history: what was inspected, when, under which standard
- Deficiency reports, open and closed, with dates
- Current contract: services, frequencies, term, renewal date
- Equipment inventory: heads, devices, extinguishers, backflows, pumps, panels
- Building list, if the customer has more than one
- Any AHJ correspondence
- Last contact date and who the contact is

Missing pieces are normal. Note the gaps in the review and proceed with what
exists, marking confidence.

## Workflow

1. **Build the account picture.** Services under contract, frequencies, equipment,
   buildings, contract dates, contacts.

2. **Run the cycle check.** What is due, coming due, and overdue by standard.
   See `references/cycles.md`. This is the single highest-value step and it is
   mechanical. Do it before anything interpretive.

3. **Age the open deficiencies.** Every open deficiency is quoted work that has
   not been sold. Sort by age and severity. See `references/triggers.md`.

4. **Scan the expansion triggers.** See `references/triggers.md`. Record an
   opportunity only when a trigger actually fired and Sobieski can actually
   perform the work.

5. **Score and rank.** See `references/scoring.md`. Rank by a composite of value,
   effort, and likelihood, and separate the retention risks from the expansion
   plays.

6. **Assess retention risk.** See `references/scoring.md`. Long gaps in contact,
   competitor bidding, a bad service experience, an unrenewed term, and price
   complaints all read differently in a recurring-inspection business than in
   software.

7. **Write the review.** See `references/output.md`. Route any customer-facing
   language through `shawn-voice`. Internal analysis does not need it.

## The core insight for this business

Most accounts do not need a new pitch. They need someone to notice that:

- The five-year internal obstruction investigation is due this year
- Fourteen extinguishers hit their six-year maintenance in March
- Eleven deficiencies from the last annual are still open, nine months on
- The fire pump has not had a flow test on record
- They added a building in 2024 that never got added to the contract

None of that is selling. It is telling a customer what they already owe. That is
the motion, and it is also why the cycle check comes before everything else.

## Cadence

Run per account before renewal and after every annual inspection. Run across the
portfolio quarterly.

The post-annual review is the important one. That is when the deficiency list is
freshest and the customer is already thinking about the building.

## Output

A written review to a path Shawn specifies, or the working directory. Default to
markdown; use the `docx` or `pdf` skill if he wants something to hand over, and
`xlsx` if the portfolio view is better as a sheet.

Never emoji. Plain status words: Current, Due, Overdue, At Risk.
