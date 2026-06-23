--!nonstrict

local InfArray = require('../../InfArray')

local Get = InfArray.Get

-- A fixed permutation of indices, built once and shared by both variants so the
-- access pattern is identical and the comparison is fair.
local function makeIndices(n: number): { number }
	local idx = table.create(n)
	for i = 1, n do
		idx[i] = i
	end
	for i = n, 2, -1 do
		local j = math.random(i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	return idx
end

return {
	title = 'Get - random-access read of N elements',
	n = 2^22,

	variants = {
		{
			name = 'InfArray',
			setup = function(n)
				local arr = InfArray.new()
				for i = 1, n do
					arr:PushBack(i)
				end
				return { arr = arr, idx = makeIndices(n) }
			end,
			run = function(state, n)
				local arr, idx = state.arr, state.idx
				local sum = 0
				for i = 1, n do
					sum += Get(arr, idx[i])
				end
				return sum
			end,
		},
		{
			name = 'Luau table',
			setup = function(n)
				local t = {}
				for i = 1, n do
					t[i] = i
				end
				return { t = t, idx = makeIndices(n) }
			end,
			run = function(state, n)
				local t, idx = state.t, state.idx
				local sum = 0
				for i = 1, n do
					sum += t[idx[i]]
				end
				return sum
			end,
		},
	},
}
