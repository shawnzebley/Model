---
name: content-engine
description: Turn real field work into LinkedIn posts, customer follow-ups, and marketing copy for fire life safety. Use when Shawn says "make a post out of this", "what can I write about this job", "I need content for the week", pastes an inspection report or deficiency list and asks for something public-facing, or asks for a content calendar or batch of posts.
---

# Content engine

Shawn's content comes from jobs, not from ideas. The raw material is inspection
reports, deficiency findings, service calls, and code questions customers actually
asked. This skill turns that into posts. It does not invent stories.

**Voice is not defined here.** Everything public-facing runs through the
`shawn-voice` skill. Load it and write to it. If the two ever disagree,
`shawn-voice` wins. This skill decides *what* to write about and *what shape it
takes*; that one decides how it sounds.

## The rule that matters most

Every post traces to something that actually happened. A real building, a real
deficiency, a real question, a real save. If there is no real thing behind it,
do not write the post. Ask Shawn for the job instead.

Generic fire safety content ("5 tips for fire alarm compliance!") is worthless.
It reads like every vendor, and it is the fastest way to sound like the marketing
team he is not.

## Workflow

1. **Get the raw material.** An inspection report, a deficiency list, a photo, a
   service ticket, a customer email, or Shawn describing a job out loud. Ask for
   specifics if what you have is vague: building type, what was found, what it
   would have caused, what got done.

2. **Run the compliance check before writing anything.** See
   `references/compliance.md`. This is not optional and it is not a formality.
   Naming the wrong customer is a real problem, not a style problem.

3. **Pick the pillar.** See `references/pillars.md`. Fire protection content works
   on a different mix than SaaS marketing. Field proof carries most of the weight.

4. **Extract the atoms.** One job usually yields two to four posts, not one. A
   single quarterly inspection can produce a finding post, a code-explainer post,
   and a "why frequency matters" post. List them before writing any.

5. **Draft in Shawn's voice.** Load `shawn-voice`. Write the hook first and check
   it against `references/hooks.md` — several common hook formulas are banned
   because they violate his voice rules.

6. **Format for the platform.** See `references/formats.md`. LinkedIn is the
   only platform that matters unless Shawn says otherwise.

7. **Hand it over with the source attached.** Show which job the post came from
   so Shawn can sanity-check the facts before it goes out.

## What Shawn's audience actually is

Property managers, facility directors, building engineers, GCs, and the occasional
AHJ. They are not fire protection professionals. They are people who own a
building and have an obligation they half understand and mostly want handled.

Write for the property manager who just got a red tag and does not know what it
means. Not for other inspectors.

## Content that works for this audience

- A deficiency found and what it would have cost if it had not been
- Plain-English translation of a code requirement they just got cited on
- What actually happens during an inspection, so it stops being a black box
- Why a frequency exists (why quarterly, why five-year, why annual)
- A straight answer to a question a customer asked this week
- What a real emergency looked like and what made the difference

## Content that does not

- Company milestones and anniversaries nobody outside the company cares about
- Holiday graphics
- Stock photos of firefighters
- "We're proud to announce"
- Anything that claims Sobieski is trusted, reliable, or committed to excellence.
  `shawn-voice` bans this outright. Show it with a job or leave it out.
- Fearmongering. Fire content slides into scare tactics easily. State what the
  code requires and what was found. The stakes are self-evident and do not need
  help.

## Batching

When Shawn asks for a week or a month of content, do not generate posts from
nothing. Ask for the last few weeks of job activity, pull the atoms from those,
and lay them out. See `references/formats.md` for the cadence.

If there is not enough real material for the volume he asked for, say so and
deliver fewer posts. Do not pad with generic filler to hit a number.

## Never

- Name a customer, building, or address without confirmed permission
- Post a photo that identifies a property with an open deficiency
- State a code interpretation as settled when the AHJ has final say
- Imply a competitor did the deficient work, even when true
- Invent a job, a number, a save, or a quote from a customer
- Use a deficiency at a current customer's building as public content while it
  is still open
