-- Per-section schedule — static, in the speaker notes.
--
--   ## Slices and Arrays {duration="20min"}
--
-- A heading with `duration` opens a section that runs until the next heading
-- marked the same way — regardless of heading level, this is a flat sequence.
-- The sum of all sections is the planned total duration of the deck.
--
-- Every slide from the first section onwards gets one line at the top of its
-- speaker notes — numbers only, `h:mm:ss`, remaining before total:
--
--   ⏱ 0:15:00/0:25:00 · 1:28:30/1:55:00
--     ^section        ^deck
--
-- The numbers are purely static, derived from the slide count (a section's
-- duration is spread evenly across its slides) — no clock is running, the line
-- only says where the plan says you are.
--
-- Counted are only the headings that revealjs actually breaks a slide at:
-- `slide-level` (2 under Quarto) and shallower. A deeper heading renders
-- inside the slide it sits in, so it is neither a slide of its own nor a
-- place to put `duration`.
--
-- The `.notes` divs it generates are the ones you would write by hand, so
-- Quarto shows them in the speaker view like any other note.

-- Accepted units, each with a short and a long spelling. Without a unit it is
-- minutes — that keeps `duration="90"` readable and makes `duration="1h30"`
-- mean what it should.
local UNITS = {
	[""] = 60, s = 1, sec = 1, m = 60, min = 60, h = 3600, hour = 3600,
}

-- Aborts the render with a readable message
local function fail(title, spec)
	io.stderr:write(string.format([[

=== slide-duration: cannot read duration ===
  File     : %s
  Heading  : %s
  duration : %s

  Expected a number plus a unit, repeatable:
  `20min`, `90` (minutes when the unit is left off), `1h30`, `2h`, `45s`.

]], PANDOC_STATE.input_files[1] or "<unknown file>", title, spec))
	os.exit(1)
end

-- Same for a `duration` that sits where no slide begins.
local function fail_deep(title, level, slide_level)
	io.stderr:write(string.format([[

=== slide-duration: heading does not start a slide ===
  File        : %s
  Heading     : %s
  level       : %d
  slide-level : %d

  A section starts at the top of a slide, so `duration` belongs on a heading
  of level %d or shallower. Deeper ones render inside the slide they sit in.

]], PANDOC_STATE.input_files[1] or "<unknown file>", title, level, slide_level, slide_level))
	os.exit(1)
end

-- The level up to which a heading breaks a slide. Pandoc hands the option over
-- in the writer options, which is where Quarto's `slide-level` (2 unless the
-- deck says otherwise) arrives; run through plain pandoc without `--slide-level`
-- nothing is set and the metadata, then that same default, has to do.
local function slide_level(doc)
	local level = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.slide_level
	if not level or level == 0 then
		local meta = doc.meta["slide-level"]
		level = meta and tonumber(pandoc.utils.stringify(meta))
	end
	return level or 2
end

-- "1h30" -> 5400, "20min" -> 1200, "90" -> 5400. nil if something does not fit
-- or nothing is left in the end (`""` and `"0min"` are not a schedule).
local function parse_duration(spec)
	local text = spec:lower():gsub("%s+", "")
	local seconds, pos = 0, 1
	while pos <= #text do
		local num, unit, next_pos = text:match("^(%d+)(%a*)()", pos)
		if not num or not UNITS[unit] then
			return nil
		end
		seconds = seconds + tonumber(num) * UNITS[unit]
		pos = next_pos
	end
	return seconds > 0 and seconds or nil
end

-- `h:mm:ss`. Splitting a section across its slides rarely divides evenly, so
-- the value can carry a fraction — snapped to the nearest whole second, which
-- is as fine as the format goes.
local function format_duration(seconds)
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

-- One line, numbers only: `⏱ remaining/total` for the section, same for the deck.
-- `used` is what the section has already spent before this slide — the slide
-- itself is still to come.
local function note_div(section, used, deck)
	local line = string.format("⏱ %s/%s · %s/%s",
		format_duration(section.seconds - used), format_duration(section.seconds),
		format_duration(deck - section.before - used), format_duration(deck))
	return pandoc.Div({ pandoc.Plain(pandoc.Str(line)) }, pandoc.Attr("", { "notes" }))
end

-- Whether the target format has slides at all.
--
-- `quarto.doc.is_format` only exists under Quarto; run through plain pandoc
-- (the tests load the filter via tests/quarto-stub.lua, which supplies exactly
-- this one function) the call fails and the deck behaviour stands.
local function is_revealjs()
	local ok, res = pcall(function()
		return quarto.doc.is_format("revealjs")
	end)
	if not ok then
		return true
	end
	return res
end

local function strip_durations(doc)
	local seen = false
	doc.blocks = doc.blocks:walk({
		Header = function(h)
			if h.attributes["duration"] then
				h.attributes["duration"] = nil
				seen = true
				return h
			end
		end,
	})
	return seen and doc or nil
end

function Pandoc(doc)
	-- This filter is only active for slides/revealjs
	if not is_revealjs() then
		return strip_durations(doc)
	end

	local level = slide_level(doc)

	-- First pass: collect the sections and count their slides. The arithmetic
	-- has to wait — a section's slide count is only settled at its end.
	local sections = {}
	for _, block in ipairs(doc.blocks) do
		if block.t == "Header" and block.level <= level then
			local spec = block.attributes["duration"]
			if spec then
				local title = pandoc.utils.stringify(block.content)
				sections[#sections + 1] = {
					title = title,
					seconds = parse_duration(spec) or fail(title, spec),
					slides = 0,
				}
			end
			local section = sections[#sections]
			if section then
				section.slides = section.slides + 1
			end
		elseif block.t == "Header" and block.attributes["duration"] then
			fail_deep(pandoc.utils.stringify(block.content), block.level, level)
		end
	end

	if #sections == 0 then
		return nil
	end

	-- Where each section starts within the deck, and how long that makes the deck.
	local deck = 0
	for _, section in ipairs(sections) do
		section.before = deck
		deck = deck + section.seconds
	end

	-- Second pass: strip `duration` and put the note behind the heading, so it
	-- sits at the top in the speaker view. Which heading is the nth slide of
	-- which section follows the same rule as above.
	local blocks = pandoc.List()
	local index, position = 0, 0
	for _, block in ipairs(doc.blocks) do
		if block.t ~= "Header" or block.level > level then
			blocks:insert(block)
		else
			if block.attributes["duration"] then
				block.attributes["duration"] = nil
				index, position = index + 1, 1
			else
				position = position + 1
			end
			blocks:insert(block)
			if index > 0 then
				local section = sections[index]
				blocks:insert(note_div(
					section, section.seconds * (position - 1) / section.slides, deck))
			end
		end
	end
	doc.blocks = blocks

	-- The planned time frame is interesting at build time, not in the deck.
	local lines = {}
	for i, section in ipairs(sections) do
		-- Singular pads with a space so the slide column stays aligned.
		lines[#lines + 1] = string.format("  %2d. %8s  %3d slide%s  %s",
			i, format_duration(section.seconds), section.slides,
			section.slides == 1 and " " or "s", section.title)
	end
	local msg = string.format("slide-duration: %d section%s, %s planned\n%s",
		#sections, #sections == 1 and "" or "s",
		format_duration(deck), table.concat(lines, "\n"))
	if not pcall(function() quarto.log.output(msg) end) then
		io.stderr:write(msg .. "\n")
	end

	return doc
end
