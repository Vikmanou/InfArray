--!nonstrict

local InfArray = require('../../InfArray')

return {
	title = 'PushBack - append N elements',
	n = 2^22,

	variants = {
		{
			name = 'InfArray',
			run = function(_, n)
				local arr = InfArray.new()
				for i = 1, n do
					arr:PushBack(i)
				end
			end,
		},
		{
			name = 'Luau table',
			run = function(_, n)
				local t = {}
				for i = 1, n do
					t[i] = i
				end
			end,
		},
	},
}
