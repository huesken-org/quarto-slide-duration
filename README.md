# quarto-slide-duration

> **Disclaimer:** built with AI

A Quarto filter that turns a planned duration per section into a countdown line
in the speaker notes of every slide. revealjs only.

> **Disclaimer:** built for my own presentations. Fit for that, not promised to
> fit anything else.

## Install

```sh
quarto add huesken-consulting/quarto-slide-duration
```

## Use

Mark a heading with `duration`. It opens a section that runs until the next
heading marked the same way — regardless of heading level, it is a flat
sequence.

```markdown
## Slices and Arrays {duration="20min"}

## Growing a slice

### Not a slide of its own

## Maps {duration="15min"}
```

Every slide from the first marked heading onwards gets one line at the top of
its speaker notes:

```
⏱ 0:15:00/0:20:00 · 1:28:30/1:55:00
  ^section          ^deck
```

Remaining before total, for the section and for the whole deck. The numbers are
static, derived from the slide count — a section's duration is spread evenly
across its slides. No clock is running; the line only says where the plan says
you are.

Counted are only the headings revealjs actually breaks a slide at: `slide-level`
— 2 unless the deck sets it — and shallower. A deeper heading renders inside the
slide it sits in, so it is neither counted nor a place for `duration`; putting
one there aborts the render. Slides before the first marked heading get no line.

**revealjs only.** In any other format the filter takes `duration` off the
headings and does nothing else.

At render time the filter also prints the plan it computed:

```
slide-duration: 2 sections, 0:35:00 planned
   1.  0:20:00    2 slides  Slices and Arrays
   2.  0:15:00    1 slide   Maps
```

### Durations

A number plus a unit, repeatable: `1h30`, `20min`, `90` (minutes when the unit
is left off), `45s`. Units are `s`/`sec`, `m`/`min`, `h`/`hour`; case and
whitespace do not matter. Anything else — an unknown unit, or a duration that
comes out as zero — aborts the render with a message naming the file and the
heading, rather than quietly producing a wrong schedule.

## Tests

Golden-file tests, run against plain pandoc — no Quarto install needed, since
the filter only touches `quarto.*` inside a `pcall`.

```sh
tests/run.sh                  # all cases
tests/run.sh units invalid-   # only cases matching a pattern
tests/run.sh --update         # rewrite expected.txt from the actual capture
```

A case is a directory under `tests/cases/` holding `input.qmd`; rendering it
captures the exit code, the pandoc native AST and stderr into `expected.txt`.
