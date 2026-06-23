--!nonstrict

local InfArray = require('../../InfArray')

return {
	title = 'Find - linear search with needle at the end',
	n = 2^22,

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
				return arr:Find(n)
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
				return table.find(t, n)
			end,
		},
	},
}
