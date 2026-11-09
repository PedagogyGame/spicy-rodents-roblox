--!strict
-- Writes docs/reports/compile_report.md from the compile result.
local Report = {}

export type Row = { [string]: any }

local function table_(rows: { Row }, cols: { { title: string, key: string } }): string
	local out = {
		"| " .. table.concat(
			(function()
				local t = {}
				for _, c in cols do
					table.insert(t, c.title)
				end
				return t
			end)(),
			" | "
		) .. " |",
	}
	local sep = {}
	for _ in cols do
		table.insert(sep, "---")
	end
	table.insert(out, "|" .. table.concat(sep, "|") .. "|")
	for _, r in rows do
		local cells = {}
		for _, c in cols do
			local v = r[c.key]
			table.insert(cells, (string.gsub(tostring(if v == nil then "" else v), "|", "\\|")))
		end
		table.insert(out, "| " .. table.concat(cells, " | ") .. " |")
	end
	return table.concat(out, "\n")
end

function Report.markdown(r: any): string
	local L = {}
	local function add(s: string)
		table.insert(L, s)
	end
	add("# Compile report: authored data -> `generated/`")
	add("")
	add(
		string.format(
			"Generated %s by `tools/compile` (Lune %s). Command: `lune run tools/compile/main.luau compile` (see `tools/compile/README.md`). Staleness gate: `lune run tools/compile/main.luau check`.",
			r.generatedAt,
			r.luneVersion
		)
	)
	add("")
	add("## Inputs")
	add("")
	add(
		"- Authored data: `data/authored/**` (HTML units), migrated once from `spec/data/*.json` by `lune run tools/compile/main.luau migrate` and validated against `data/schema/*.schema.json`."
	)
	add(
		string.format(
			"- Harvest: `data/harvest/routes.json` and `forks.json` pinned to HTML SHA-256 `%s`.",
			r.harvestSha
		)
	)
	add(
		"- Unit conversion: every number the schemas mark `x-unit: u` or `u/s` is multiplied by 2.5 on the shortest decimal representation (so 18.04 u becomes exactly 45.1 st); angles, seconds and counts are untouched. Nested v5.4 constant blocks in the wildlife files that the schemas do not annotate stay in HTML units and are emitted under `htmlUnits` keys."
	)
	add("")
	add("## Count comparisons")
	add("")
	add(table_(r.comparisons, {
		{ title = "what", key = "what" },
		{ title = "expected", key = "expected" },
		{ title = "actual", key = "actual" },
		{ title = "status", key = "status" },
		{ title = "note", key = "note" },
	}))
	add("")
	add("## Lots per district")
	add("")
	add(table_(r.lotsPerDistrict, {
		{ title = "district", key = "district" },
		{ title = "lots", key = "count" },
		{ title = "with footprint", key = "withFootprint" },
		{ title = "with facing or yaw", key = "withFacing" },
		{ title = "interiors", key = "interiors" },
	}))
	add("")
	add("Distinct lot types: " .. tostring(r.lotTypeCount) .. " (" .. r.lotTypes .. ").")
	add("")
	add("## Validation and invariants")
	add("")
	add(string.format("- Schema validation: %d file(s), %d error(s).", r.filesValidated, r.schemaErrors))
	add(string.format("- Invariants checked: %d, failed: %d.", r.invariantsChecked, r.invariantsFailed))
	for _, w in r.warnings :: { string } do
		add("- warning: " .. w)
	end
	add("")
	add("## Generated modules (`generated/`, Rojo: `ReplicatedStorage.Shared.Generated`)")
	add("")
	add(table_(r.generated, {
		{ title = "module", key = "name" },
		{ title = "records", key = "records" },
		{ title = "bytes", key = "bytes" },
		{ title = "require (ms, Lune)", key = "requireMs" },
		{ title = "source", key = "source" },
	}))
	add("")
	add(
		string.format(
			"Total %d files, %d bytes; largest %s (%d bytes, %.1f ms to require under Lune). Routes are chunked at about %d KB per module; `Index.luau` lists the chunks and counts.",
			r.generatedCount,
			r.generatedBytes,
			r.largest.name,
			r.largest.bytes,
			r.largest.requireMs,
			r.chunkKb
		)
	)
	add("")
	add("## Notes for the lead")
	add("")
	for _, n in r.notes :: { string } do
		add("- " .. n)
	end
	return table.concat(L, "\n") .. "\n"
end

return Report
