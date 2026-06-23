--!nonstrict
--[[
    Pretty-printing for benchmark results.
    Markdown
]]

local report = {}


local function formatPerOp(seconds: number): string
	local ns = seconds * 1e9
	if ns < 1e3 then
		return string.format('%.1f ns', ns)
	elseif ns < 1e6 then
		return string.format('%.2f µs', ns / 1e3)
	elseif ns < 1e9 then
		return string.format('%.2f ms', ns / 1e6)
	end

	return string.format('%.2f s', seconds)
end


local function formatTotal(seconds: number): string
	if seconds < 1 then
		return string.format('%.2f ms', seconds * 1e3)
	end

	return string.format('%.3f s', seconds)
end


local function formatRate(rate: number): string
	if rate >= 1e9 then
		return string.format('%.2f B/s', rate / 1e9)
	elseif rate >= 1e6 then
		return string.format('%.2f M/s', rate / 1e6)
	elseif rate >= 1e3 then
		return string.format('%.2f K/s', rate / 1e3)
	end
	
	return string.format('%.0f /s', rate)
end

-- Ratio vs baseline
local function formatRatio(r, baselineName: string): string
	if r.name == baselineName then
		return '1.00× (baseline)'
	elseif r.ratio >= 1 then
		return string.format('%.2f× slower', r.ratio)
	end
	
	return string.format('%.2f× faster', 1 / r.ratio)
end

local function formatN(n: number): string
	-- Luau numeric
	local s = string.format('%d', n)

	local out, count = '', 0
	for i = #s, 1, -1 do
		out = s:sub(i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = '_' .. out
		end
	end

	return out
end

report.formatN = formatN

-- Console rendering

local DIM = '\27[2m'
local BOLD = '\27[1m'
local GREEN = '\27[32m'
local YELLOW = '\27[33m'
local RESET = '\27[0m'

local function pad(s: string, width: number): string
	-- µ and box chars are multi-byte
	local len = utf8.len(s) or #s
	if len >= width then return s end
	return s .. string.rep(' ', width - len)
end

function report.console(run)
	print(`\n{BOLD}{run.title}{RESET}  {DIM}(n = {formatN(run.n)}){RESET}`)
	if run.note then
		print(`{DIM}{run.note}{RESET}`)
	end

	local cols = { 'Implementation', 'Time/op', 'Total', 'Throughput', 'vs baseline' }
	local widths = { 16, 11, 11, 13, 20 }

	local header = ''
	for i, c in cols do
		header ..= pad(c, widths[i]) .. '  '
	end
	print(DIM .. header .. RESET)

	-- Fastest variant gets green highlight
	local fastest = run.results[1]
	for _, r in run.results do
		if r.best < fastest.best then
			fastest = r
		end
	end

	for _, r in run.results do
		local row = pad(r.name, widths[1])
			.. '  '
			.. pad(formatPerOp(r.perOp), widths[2])
			.. '  '
			.. pad(formatTotal(r.best), widths[3])
			.. '  '
			.. pad(formatRate(r.opsPerSec), widths[4])
			.. '  '
			.. pad(formatRatio(r, run.baseline), widths[5])

		local colour = if r == fastest then GREEN elseif r.name == run.baseline then YELLOW else ''
		print((colour ~= '' and colour or '') .. row .. (colour ~= '' and RESET or ''))
	end
end

-- Markdown

function report.markdown(run): string
	local lines = {}
	table.insert(lines, `### {run.title}`)
	table.insert(lines, '')
	table.insert(lines, `Workload size: \`n = {formatN(run.n)}\``)
	if run.note then
		table.insert(lines, '')
		table.insert(lines, `> {run.note}`)
	end
	table.insert(lines, '')
	table.insert(lines, '| Implementation | Time/op | Total | Throughput | vs baseline |')
	table.insert(lines, '| -------------- | ------- | ----- | ---------- | ----------- |')

	for _, r in run.results do
		local name = if r.name == run.baseline then `**{r.name}**` else r.name
		table.insert(
			lines,
			string.format(
				'| %s | %s | %s | %s | %s |',
				name,
				formatPerOp(r.perOp),
				formatTotal(r.best),
				formatRate(r.opsPerSec),
				formatRatio(r, run.baseline)
			)
		)
	end
	
	table.insert(lines, '')

	return table.concat(lines, '\n')
end

return report
