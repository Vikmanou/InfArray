--!strict

local test = require('@std/test')
local InfArray = require('../InfArray')

test.case('GetChunk returns the backing chunk, nil for an absent one', function(asserts)
	local arr = InfArray.new(5, 2)
	local chunk = arr:GetChunk(1)
	asserts.that(chunk ~= nil)
	asserts.eq((chunk :: any)[1], 2)
	asserts.eq(arr:GetChunk(99), nil)
end)

test.case('SetChunk: dense data derives length from #value', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, { 10, 20, 30 })
	asserts.eq(arr:Length(), 3)
	asserts.eq(arr:Count(), 3)
	asserts.eq(arr:Get(2), 20)
end)

test.case('SetChunk: explicit len counts only present elements in sparse data', function(asserts)
	local arr = InfArray.new()
	local sparse = {}
	sparse[1] = 'a'
	sparse[3] = 'c'
	arr:SetChunk(1, sparse, 3)
	asserts.eq(arr:Length(), 3)
	asserts.eq(arr:Count(), 2)
	asserts.eq(arr:Get(1), 'a')
	asserts.eq(arr:Get(2), nil)
	asserts.eq(arr:Get(3), 'c')
end)

test.case('SetChunk: a second chunk extends logical length across the LIMIT boundary', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, { 1, 2 })
	arr:SetChunk(2, { 'x' })
	asserts.eq(arr:Length(), InfArray.LIMIT + 1)
	asserts.eq(arr:Count(), 3)
	asserts.eq(arr:Get(InfArray.LIMIT + 1), 'x')
end)
