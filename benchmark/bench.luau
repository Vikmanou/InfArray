--!nonstrict
--[[

    benchmark/bench.luau

    Spec structure:
        {
            title = 'PushBack (append N elements)',    -- shown as the section heading
            n = 1_000_000,                             -- the workload size
            note = 'optional one-line caveat',         -- optional

            variants = {
                {
                    name = 'InfArray',
                    setup = function(n) return nil end, -- setup runs UNTIMED before every run
                    run = function(state, n) ... end,
                },
                { name = 'Luau table', run = function(_, n) ... end },
            },
        }
]]

local time = require('@lute/time')

local bench = {}

local DEFAULTS = {
	warmup = 2, -- discarded samples
	samples = 6
}

local BASELINE_NAME = 'Luau table'


local function timeOnce(variant, n: number): number
	local state = if variant.setup then variant.setup(n) else nil
	local t0 = time.now()
	variant.run(state, n)
	return time.since(t0)
end


local function measure(variant, n: number, opts)
	for _ = 1, opts.warmup do
		timeOnce(variant, n)
	end

	local samples = table.create(opts.samples)
	for i = 1, opts.samples do
		samples[i] = timeOnce(variant, n)
	end
	table.sort(samples)

	local best = samples[1]
	local median = samples[(opts.samples - opts.samples % 2) // 2 + 1]

	return {
		name = variant.name,
		best = best,
		median = median,
		perOp = best / n,
		opsPerSec = n / best,
	}
end

-- Returns: { title, n, note, baseline = <name>, results = { <measured variant>... } }
-- Each result also gets `.ratio` -- how many times slower than the baseline
-- 1.0 for the baseline itself
function bench.run(spec, overrides)
	local opts = {
		warmup = (overrides and overrides.warmup) or DEFAULTS.warmup,
		samples = (overrides and overrides.samples) or DEFAULTS.samples,
	}

	local n = spec.n
	if overrides and overrides.scale then
		n = math.max(1, math.floor(n * overrides.scale))
	end

	local results = {}
	for _, variant in spec.variants do
		table.insert(results, measure(variant, n, opts))
	end

	-- Pick the fastest variant
	local baseline
	for _, r in results do
		if r.name == BASELINE_NAME then
			baseline = r
			break
		end
	end
	
	if not baseline then
		baseline = results[1]
		for _, r in results do
			if r.best < baseline.best then
				baseline = r
			end
		end
	end

	for _, r in results do
		r.ratio = r.best / baseline.best
	end

	return {
		title = spec.title,
		n = n,
		note = spec.note,
		baseline = baseline.name,
		results = results,
	}
end

return bench
