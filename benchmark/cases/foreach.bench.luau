--!nonstrict

local InfArray = require('../../InfArray')

return {
	title = '`for index, value in arr` via __iter',
	n = 2^22,
	note = '__iter pays a closure call per element',

	variants = {
		{
			name = 'InfArray',
			setup = function(n)
				local arr = InfArray.new()
				for i = 1, n do
					arr:PushBack(i)
				end
				return arr
			end,
			run = function(arr, _)
				local sum = 0
				for _, value in arr do
					sum += value
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
				return t
			end,
			run = function(t, _)
				local sum = 0
				for _, value in t do
					sum += value
				end
				return sum
			end,
		},
	},
}
