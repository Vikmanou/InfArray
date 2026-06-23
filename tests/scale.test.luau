--!strict

-- Battle test beyond 2^26 values

local test = require('@std/test')
local InfArray = require('../InfArray')

local LIMIT = InfArray.LIMIT
local HIGH_CHUNK = 2 ^ 27

test.case('locate maps indices on both sides of the LIMIT boundary', function(asserts)
	local c, p = InfArray.locate(LIMIT)
	asserts.eq(c, 1)
	asserts.eq(p, LIMIT)

	c, p = InfArray.locate(LIMIT + 1)
	asserts.eq(c, 2)
	asserts.eq(p, 1)

	c, p = InfArray.locate(2 * LIMIT)
	asserts.eq(c, 2)
	asserts.eq(p, LIMIT)

	c, p = InfArray.locate(2 * LIMIT + 1)
	asserts.eq(c, 3)
	asserts.eq(p, 1)
end)

test.case('locate stays exact near 2^53 without bit truncation', function(asserts)
	local topIndex = (HIGH_CHUNK - 1) * LIMIT + 1
	local c, p = InfArray.locate(topIndex)
	asserts.eq(c, HIGH_CHUNK)
	asserts.eq(p, 1)
end)

test.case('Set / Get address a chunk placed past 2^26', function(asserts)
	local arr = InfArray.new()

	arr:SetChunk(2, table.create(5, 0), 5)

	arr:Set(LIMIT + 3, 99)
	asserts.eq(arr:Get(LIMIT + 3), 99)
	asserts.eq(arr:Get(LIMIT + 1), 0)
	asserts.eq(arr:Get(LIMIT + 5), 0)
end)

test.case('Set / Get reach a chunk near the 2^53 ceiling', function(asserts)
	local arr = InfArray.new()
	local base = (HIGH_CHUNK - 1) * LIMIT

	arr:SetChunk(HIGH_CHUNK, { 42 }, 1)
	asserts.eq(arr:Get(base + 1), 42)
	asserts.eq(arr:Length(), base + 1)
	asserts.eq(arr:Count(), 1)
end)

test.case('Iterate reports correct global indices across a chunk boundary', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, { 10, 20 }, 2)
	arr:SetChunk(2, { 30 }, 1)

	local seen: { { any } } = {}
	arr:Iterate(function(index: number, value: any)
		table.insert(seen, { index, value })
		return nil
	end)

	asserts.eq(#seen, 3)
	asserts.eq(seen[1], { 1, 10 })
	asserts.eq(seen[2], { 2, 20 })
	asserts.eq(seen[3], { LIMIT + 1, 30 })
end)

test.case('Find returns a global index that lives past 2^26', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, { 10, 20 }, 2)
	arr:SetChunk(2, { 30 }, 1)
	asserts.eq(arr:Find(30), LIMIT + 1)
end)

test.case('an array holds and reports more than 2^26 present values', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, table.create(LIMIT, 1), LIMIT)
	arr:SetChunk(2, { 1, 1, 1 }, 3)

	asserts.eq(arr:Count(), LIMIT + 3)
	asserts.eq(arr:Length(), LIMIT + 3)
	asserts.that(arr:Count() > LIMIT, 'count must exceed the per-table limit')

	asserts.eq(arr:Get(LIMIT), 1)
	asserts.eq(arr:Get(LIMIT + 1), 1)
	asserts.eq(arr:Get(LIMIT + 3), 1)
	asserts.eq(arr:Get(LIMIT + 4), nil)
end)

test.case('removing across the 2^26 seam keeps Count and Length honest', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, table.create(LIMIT, 1), LIMIT)
	arr:SetChunk(2, { 1, 1, 1 }, 3)

	arr:RemoveIndex(LIMIT)
	arr:RemoveIndex(LIMIT + 1)

	asserts.eq(arr:Get(LIMIT), nil)
	asserts.eq(arr:Get(LIMIT + 1), nil)
	asserts.eq(arr:Count(), LIMIT + 1)
	asserts.eq(arr:Length(), LIMIT + 3)
end)

test.case('Find scans through a full first chunk to a needle past 2^26', function(asserts)
	local arr = InfArray.new()
	arr:SetChunk(1, table.create(LIMIT, 1), LIMIT)
	arr:SetChunk(2, { 1, 1, 1 }, 3)

	arr:Set(LIMIT + 2, 'sentinel')
	asserts.eq(arr:Find('sentinel'), LIMIT + 2)
end)
