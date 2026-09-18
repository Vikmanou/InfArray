--!strict

local test = require('@std/test')
local InfArray = require('../InfArray')

test.case('new: empty array reports zero length and count', function(asserts)
	local arr = InfArray.new()
	asserts.eq(arr:Length(), 0)
	asserts.eq(arr:Count(), 0)
end)

test.case('new: sized with a value fills every slot as present', function(asserts)
	local arr = InfArray.new(5, 0)
	asserts.eq(arr:Length(), 5)
	asserts.eq(arr:Count(), 5)
	asserts.eq(arr:Get(1), 0)
	asserts.eq(arr:Get(5), 0)
end)

test.case('new: sized without a value has logical length but no present elements', function(asserts)
	local arr = InfArray.new(5)
	asserts.eq(arr:Length(), 5)
	asserts.eq(arr:Count(), 0)
	asserts.eq(arr:Get(3), nil)
end)

test.case('new: zero size stays empty', function(asserts)
	local arr = InfArray.new(0)
	asserts.eq(arr:Length(), 0)
	asserts.eq(arr:Count(), 0)
end)

test.case('LIMIT constant is 2^26', function(asserts)
	asserts.eq(InfArray.LIMIT, 2 ^ 26)
end)

test.case('GetChunkAndPosition: maps the first index to chunk 1, position 1', function(asserts)
	local arr = InfArray.new()
	local first = { 'a' }
	arr:SetChunk(1, first, 1)

	local chunk, pos = arr:GetChunkAndPosition(1)
	asserts.eq(chunk, first)
	asserts.eq(pos, 1)
end)

test.case('GetChunkAndPosition: last index of chunk 1 is at LIMIT', function(asserts)
	local arr = InfArray.new()
	local first = { 'a' }
	arr:SetChunk(1, first, 1)

	local chunk, pos = arr:GetChunkAndPosition(InfArray.LIMIT)
	asserts.eq(chunk, first)
	asserts.eq(pos, InfArray.LIMIT)
end)

test.case('GetChunkAndPosition: first index of chunk 2 wraps to position 1', function(asserts)
	local arr = InfArray.new()
	local second = { 'b' }
	arr:SetChunk(2, second, 1)

	local chunk, pos = arr:GetChunkAndPosition(InfArray.LIMIT + 1)
	asserts.eq(chunk, second)
	asserts.eq(pos, 1)
end)
