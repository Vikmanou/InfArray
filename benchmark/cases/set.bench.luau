--!nonstrict

local InfArray = require('../../InfArray')

local Set = InfArray.Set

return {
	title = 'Set - overwrite N in-range elements',
	n = 2^22,

	variants = {
		{
			name = 'InfArray',
			setup = function(n)
				return InfArray.new(n, 0)
			end,
			run = function(arr, n)
				for i = 1, n do
					Set(arr, i, i)
				end
			end,
		},
		{
			name = 'Luau table',
			setup = function(n)
				return table.create(n, 0)
			end,
			run = function(t, n)
				for i = 1, n do
					t[i] = i
				end
			end,
		},
	},
}
