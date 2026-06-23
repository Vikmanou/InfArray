--!nonstrict

local InfArray = require('../../InfArray')

local Get = InfArray.Get

return {
	title = 'Get - sequential read of N elements',
	n = 2^22,
	note = 'InfArray uses the hoisted free function `local Get = InfArray.Get`.',

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
			run = function(arr, n)
				local sum = 0
				for i = 1, n do
					sum += Get(arr, i)
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
			run = function(t, n)
				local sum = 0
				for i = 1, n do
					sum += t[i]
				end
				return sum
			end,
		},
	},
}
