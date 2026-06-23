--!strict

local test = require('@std/test')
local InfArray = require('../InfArray')

test.case('Iterate visits present elements in order and skips holes', function(asserts)
	local arr = InfArray.new()
	for i = 1, 5 do
		arr:PushBack(i * 10)
	end
	arr:RemoveIndex(3)

	local seen: { { any } } = {}
	arr:Iterate(function(index, value)
		table.insert(seen, { index, value })
		return nil
	end)

	asserts.eq(#seen, 4)
	asserts.eq(seen[1], { 1, 10 })
	asserts.eq(seen[3], { 4, 40 })
end)

test.case('Iterate stops early when the callback returns true', function(asserts)
	local arr = InfArray.new()
	for i = 1, 5 do
		arr:PushBack(i)
	end

	local visited = 0
	arr:Iterate(function(index, value)
		visited += 1
		return index == 2
	end)

	asserts.eq(visited, 2)
end)

test.case('__iter drives `for index, value in arr` in order, skipping holes', function(asserts)
	local arr = InfArray.new()
	for i = 1, 5 do
		arr:PushBack(i * 10)
	end
	arr:RemoveIndex(3)

	local seen: { { any } } = {}
	for index, value in arr do
		table.insert(seen, { index, value })
	end

	asserts.eq(#seen, 4)
	asserts.eq(seen[1], { 1, 10 })
	asserts.eq(seen[3], { 4, 40 })
end)

test.case('__iter agrees with Iterate over the same array', function(asserts)
	local arr = InfArray.new()
	for i = 1, 20 do
		arr:PushBack(i)
	end
	arr:RemoveIndex(1)
	arr:RemoveIndex(10)
	arr:RemoveIndex(20)

	local fromIterate: { { any } } = {}
	arr:Iterate(function(index, value)
		table.insert(fromIterate, { index, value })
		return nil
	end)

	local k = 0
	for index, value in arr do
		k += 1
		asserts.eq({ index, value }, fromIterate[k])
	end
	asserts.eq(k, #fromIterate)
	asserts.eq(k, arr:Count())
end)

test.case('__iter yields nothing for an empty array', function(asserts)
	local arr = InfArray.new()
	local count = 0
	for _ in arr do
		count += 1
	end
	asserts.eq(count, 0)
end)

test.case('__iter `break` stops cleanly mid-iteration', function(asserts)
	local arr = InfArray.new()
	for i = 1, 5 do
		arr:PushBack(i)
	end

	local visited = 0
	for index in arr do
		visited += 1
		if index == 2 then
			break
		end
	end
	asserts.eq(visited, 2)
end)

test.case('Find returns the first matching global index, nil when absent', function(asserts)
	local arr = InfArray.new()
	arr:PushBack('a')
	arr:PushBack('b')
	arr:PushBack('c')
	asserts.eq(arr:Find('b'), 2)
	asserts.eq(arr:Find('missing'), nil)
end)

test.case('Find scans past holes using the tracked length', function(asserts)
	local arr = InfArray.new()
	arr:PushBack(1)
	arr:PushBack(2)
	arr:PushBack(3)
	arr:RemoveIndex(1)
	asserts.eq(arr:Find(3), 3)
end)

test.case('Transform applies the update over a contiguous range', function(asserts)
	local arr = InfArray.new()
	for i = 1, 5 do
		arr:PushBack(i)
	end
	arr:Transform(1, 5, 1, function(index, value: number)
		return value * 2
	end)
	asserts.eq(arr:Get(1), 2)
	asserts.eq(arr:Get(5), 10)
end)

test.case('Transform maintains Count when it fills holes or clears values', function(asserts)
	local arr = InfArray.new()
	for i = 1, 4 do
		arr:PushBack(i)
	end
	arr:RemoveIndex(2) -- one hole; Count is now 3, Length still 4

	-- Fill every index in [1, 4]: the hole at 2 becomes present again.
	arr:Transform(1, 4, 1, function(index: number, value)
		return index * 100
	end)
	asserts.eq(arr:Get(2), 200)
	asserts.eq(arr:Count(), 4)

	-- Now clear them all back to holes.
	arr:Transform(1, 4, 1, function(index, value)
		return nil
	end)
	asserts.eq(arr:Count(), 0)
end)

test.case('Transform honors the step, leaving skipped indices untouched', function(asserts)
	local arr = InfArray.new()
	for _ = 1, 6 do
		arr:PushBack(0)
	end
	arr:Transform(1, 6, 2, function(index, value)
		return 1
	end)
	asserts.eq(arr:Get(1), 1)
	asserts.eq(arr:Get(2), 0)
	asserts.eq(arr:Get(3), 1)
	asserts.eq(arr:Get(4), 0)
	asserts.eq(arr:Get(5), 1)
	asserts.eq(arr:Get(6), 0)
end)
