-- Stand-in for the `quarto` global that Quarto injects into filters.
--
-- slide-duration.lua asks `quarto.doc.is_format` whether it is producing a deck
-- — everything it does is for the speaker view of RevealJS. Plain pandoc has no
-- such function, so the tests load this wrapper instead of the filter itself: it
-- defines just enough of `quarto` to answer that one question, then loads the
-- real filter and hands its filter table to pandoc unchanged.
--
-- `quarto.log` stays undefined on purpose: the filter reports its planned
-- schedule through it inside a pcall and falls back to stderr, and stderr is
-- what the goldens capture.
--
-- TEST_FILTER  path of the filter to load
-- TEST_FORMAT  format `quarto.doc.is_format` reports (see the `format` file of
--              a test case; default revealjs)

local format = os.getenv("TEST_FORMAT") or "revealjs"

quarto = {
  doc = {
    is_format = function(f)
      return f == format
    end,
  },
}

return dofile(assert(os.getenv("TEST_FILTER"), "TEST_FILTER is not set"))
