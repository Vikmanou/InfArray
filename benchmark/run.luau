--[[

    benchmark/run.luau

    Benchmarks. Run from the repo root:

        lute run benchmark/run.luau                  -- print results to the console
        lute run benchmark/run.luau --md             -- also update benchmark/README.md
        lute run benchmark/run.luau --filter get     -- only benchmarks whose title matches
        lute run benchmark/run.luau --samples 10     -- more timed samples (less noise)
        lute run benchmark/run.luau --scale 0.1      -- shrink every workload to 10% (quick)

    Each benchmark compares InfArray against a Luau table on the same
    workload. Workloads stay under Luau's 2^26 table limit.

    To add a benchmark: drop a new `*.bench.luau` in `cases/` and add a
    `require` for it to the `SPECS` table below.
]]

local fs = require('@std/fs')
local process = require('@std/process')
local system = require('@std/system')

local bench = require('./bench')
local report = require('./report')

local SPECS = {
	require('./cases/pushback.bench'),
	require('./cases/set.bench'),
	require('./cases/get-sequential.bench'),
	require('./cases/get-random.bench'),
	require('./cases/iterate.bench'),
	require('./cases/foreach.bench'),
	require('./cases/find.bench'),
}

local README_PATH = './benchmark/README.md'
local START_MARK = '<!-- BENCH:START -->'
local END_MARK = '<!-- BENCH:END -->'

local opts = {
	writeMd = false,
	filter = nil :: string?,
	samples = nil :: number?,
	scale = nil :: number?,
}

do
	-- args[1] is the script path itself
	local args = process.args

	local i = 2
	while i <= #args do
		local a = args[i]

		if a == '--md' or a == '--write' then
			opts.writeMd = true
		elseif a == '--filter' then
			i += 1
			opts.filter = args[i]
		elseif a == '--samples' then
			i += 1
			opts.samples = tonumber(args[i])
		elseif a == '--scale' then
			i += 1
			opts.scale = tonumber(args[i])
		elseif a == '--help' or a == '-h' then
			print('Usage: lute run benchmark/run.luau [--md] [--filter <text>] [--samples N] [--scale F]')
			process.exit(0)
		else
			print(`Unknown argument: {a}  (try --help)`)
			process.exit(1)
		end

		i += 1
	end
end


local function cpuModel(): string
	local ok, cpus = pcall(system.cpus)
	if ok and cpus and cpus[1] and cpus[1].model then
		return (cpus[1].model :: string):gsub('%s+$', '')
	end
	return 'unknown CPU'
end


local function envLines(): { string }
	return {
		`CPU:      {cpuModel()}`,
		`OS:       {system.os} ({system.arch})`,
		`Date:     {os.date('%Y-%m-%d %H:%M')}`,
	}
end


local function matches(title: string): boolean
	if not opts.filter then return true end
	return string.find(title:lower(), opts.filter:lower(), 1, true) ~= nil
end

local runOverrides = { samples = opts.samples, scale = opts.scale }

print(string.rep('=', 60))
print('InfArray benchmarks — InfArray vs. a regular Luau table')
print(string.rep('=', 60))
for _, line in envLines() do
	print(line)
end
print(`Settings: samples={opts.samples or 6}, scale={opts.scale or 1}`)

local runs = {}
for _, spec in SPECS do
	if matches(spec.title) then
		local result = bench.run(spec, runOverrides)
		report.console(result)
		table.insert(runs, result)
	end
end

if #runs == 0 then
	print('\nNo benchmarks matched the filter.')
	process.exit(0)
end


if opts.writeMd then
	local sections = {}

	table.insert(sections, '## Results')
	table.insert(sections, '')
	table.insert(sections, '```')
	for _, line in envLines() do
		table.insert(sections, line)
	end
	table.insert(sections, '```')
	table.insert(sections, '')
	for _, run in runs do
		table.insert(sections, report.markdown(run))
	end
	
	local block = table.concat(sections, '\n')

	if not fs.exists(README_PATH) then
		print(`\n{README_PATH} not found — skipping markdown update.`)
	else
		local md = fs.readFileToString(README_PATH)
		local s = string.find(md, START_MARK, 1, true)
		local e = string.find(md, END_MARK, 1, true)
		if s and e then
			local before = string.sub(md, 1, s + #START_MARK - 1)
			local after = string.sub(md, e)
			md = before .. '\n' .. block .. '\n' .. after
			fs.writeStringToFile(README_PATH, md)
			print(`\nUpdated results in {README_PATH}`)
		else
			print(`\nCould not find {START_MARK} / {END_MARK} markers in {README_PATH}.`)
		end
	end
end

print('\nDone.')
