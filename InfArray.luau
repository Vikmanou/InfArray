--!native
--!optimize 2

--[[

    InfArray.luau
    @Syveric

    Bypass Luau's internal table size limit of 2^26
    by chunking values into segments. Indices use integer math, so
    the array is valid up to 2^53, the largest exact integer a Luau number holds.

    Removals leave nil holes, and since per-chunk logical lengths are tracked explicitly,
    the code never relies on `#` over a chunk (which is undefined once it has holes).

        Length() -- highest assigned index, holes included.
        Count()  -- number of present (non-nil) elements.
]]

-- Luau caps the array length at 2^MAXBITS, MAXBITS = 26.
-- See ltable.cpp: https://github.com/luau-lang/luau/blob/master/VM/src/ltable.cpp
local LIMIT_BITS = 26
local LIMIT = 2 ^ LIMIT_BITS -- 67108864 elements per chunk

local APPEND_PREALLOC = math.min(2 ^ 16, LIMIT)

type Chunk = { any }

export type InfArray = typeof(setmetatable(
	{} :: {
		_chunks: { Chunk },
		_lens: { number }, -- length per chunk, holes included
		_length: number, -- length of the whole array, holes included
		_count: number, -- number of present (non nil) elements
	},
	{} :: { __index: any }
))


local function locateWithIndex(index: number): (number, number)
	local i = index - 1
	local chunkIndex = i // LIMIT
	return chunkIndex + 1, i - chunkIndex * LIMIT + 1
end


local InfArray = { LIMIT = LIMIT, locate = locateWithIndex }
InfArray.__index = InfArray

function InfArray.new(size: number?, value: any?): InfArray
	local self = setmetatable({
		_chunks = {},
		_lens = {},
		_length = 0,
		_count = 0
	}, InfArray)

	if size and size > 0 then
		local chunkCount = (size - 1) // LIMIT + 1

		for i = 1, chunkCount do
			local chunkSize = if i < chunkCount then LIMIT else size - (chunkCount - 1) * LIMIT
			self._chunks[i] = table.create(chunkSize, value)
			self._lens[i] = chunkSize
		end

		self._length = size
		self._count = if value ~= nil then size else 0
	end

	return self
end


function InfArray.Get(self: InfArray, index: number): any?
	local chunkIndex, pos = locateWithIndex(index)
	local chunk = self._chunks[chunkIndex]
	return chunk and chunk[pos]
end


-- In-range O(1) write. No-op if the index's chunk doesn't exist yet; use
-- PushBack or new(size)/SetChunk to grow the array.
function InfArray.Set(self: InfArray, index: number, value: any?)
	local chunkIndex, pos = locateWithIndex(index)
	local chunk = self._chunks[chunkIndex]
	if not chunk then return end

	local old = chunk[pos]
	chunk[pos] = value

	if old == nil then
		if value ~= nil then
			self._count += 1
		end
	elseif value == nil then
		self._count -= 1
	end

	if value ~= nil and pos > self._lens[chunkIndex] then
		self._lens[chunkIndex] = pos

		local logical = (chunkIndex - 1) * LIMIT + pos
		if logical > self._length then
			self._length = logical
		end
	end
end


function InfArray.GetChunk(self: InfArray, index: number): Chunk?
	return self._chunks[index]
end


-- Replace an entire chunk
function InfArray.SetChunk(self: InfArray, chunkIndex: number, value: Chunk, len: number?)
	local oldChunk = self._chunks[chunkIndex]
	if oldChunk then
		local oldLen = self._lens[chunkIndex]
		for i = 1, oldLen do
			if oldChunk[i] ~= nil then
				self._count -= 1
			end
		end
	end

	local newLen = len or #value
	for i = 1, newLen do
		if value[i] ~= nil then
			self._count += 1
		end
	end

	self._lens[chunkIndex] = newLen
	self._chunks[chunkIndex] = value

	local logical = (chunkIndex - 1) * LIMIT + newLen
	if logical > self._length then
		self._length = logical
	end
end


function InfArray.GetChunkAndPosition(self: InfArray, index: number): (Chunk?, number)
	local chunkIndex, pos = locateWithIndex(index)
	return self._chunks[chunkIndex], pos
end


function InfArray.PushBack(self: InfArray, value: any): number
	local index = self._length + 1
	local chunkIndex, pos = locateWithIndex(index)

	local chunk = self._chunks[chunkIndex]
	if not chunk then
		chunk = table.create(APPEND_PREALLOC)
		self._chunks[chunkIndex] = chunk
		self._lens[chunkIndex] = 0
	end

	chunk[pos] = value
	self._lens[chunkIndex] = pos
	self._length = index
	self._count += 1

	return index
end

-- Note: Leaves a nil hole. Logical length is unchanged.
function InfArray.RemoveIndex(self: InfArray, index: number)
	local chunkIndex, pos = locateWithIndex(index)
	local chunk = self._chunks[chunkIndex]
	if not chunk then return end

	if chunk[pos] ~= nil then
		chunk[pos] = nil
		self._count -= 1
	end
end

-- Holes are skipped.
-- Prefer IterateChunks for bulk throughput
function InfArray.__iter(self: InfArray): () -> (number?, any)
	local chunks, lens = self._chunks, self._lens
	local chunkCount = #chunks
	local chunkIdx = 1
	local pos = 0
	local currentChunk = chunks[1]
	local len = lens[1] or 0
	local base = 0 -- (chunkIdx - 1) * LIMIT, updated only when the chunk changes

	return function(): (number?, any)
		while true do
			pos += 1

			if pos > len then
				-- Skip empty chunks
				repeat
					chunkIdx += 1
					if chunkIdx > chunkCount then return nil end
					currentChunk = chunks[chunkIdx]
					len = lens[chunkIdx]
				until len > 0

				pos = 1
				base = (chunkIdx - 1) * LIMIT
			end

			local value = currentChunk[pos]
			if value ~= nil then
				return base + pos, value
			end
		end
	end
end

-- callback(index, value) -> boolean? ; return true to stop. Holes are skipped.
function InfArray.Iterate(self: InfArray, callback: (index: number, value: any) -> boolean?)
	local chunks, lens = self._chunks, self._lens

	for i = 1, #chunks do
		local chunk = chunks[i]
		local len = lens[i]

		local base = (i - 1) * LIMIT
		for j = 1, len do
			local value = chunk[j]
			if value ~= nil then
				if callback(base + j, value) then
					return
				end
			end
		end
	end
end

-- return true to stop
-- Hands raw chunks to the caller 
-- The caller must nil-check chunk[j] itself
-- Fastest for bulk work
function InfArray.IterateChunks(self: InfArray, callback: (chunk: Chunk, base: number, len: number) -> boolean?)
	local chunks, lens = self._chunks, self._lens

	for i = 1, #chunks do
		if callback(chunks[i], (i - 1) * LIMIT, lens[i]) then
			return
		end
	end
end

-- First global index whose value == needle or nil
function InfArray.Find(self: InfArray, needle: any): number?
	local chunks, lens = self._chunks, self._lens

	for i = 1, #chunks do
		local chunk = chunks[i]
		-- Scan to the tracked length so holes don't cut the search short.
		local len = lens[i]
		for j = 1, len do
			if chunk[j] == needle then
				return (i - 1) * LIMIT + j
			end
		end
	end

	return nil
end

-- updateFunc(index, value) -> newValue, applied over [start, stop] by step.
-- May turn holes into values (or back); Count() stays correct.
function InfArray.Transform(
	self: InfArray,
	start: number,
	stop: number,
	step: number,
	updateFunc: (index: number, value: any) -> any
)
	local chunks = self._chunks

	local index = start
	while index <= stop do
		local chunkIndex = locateWithIndex(index)
		local chunk = chunks[chunkIndex]
		local chunkEnd = chunkIndex * LIMIT

		if chunk then
			local base = (chunkIndex - 1) * LIMIT
			local limit = math.min(chunkEnd, stop)
			for i = index, limit, step do
				local pos = i - base
				local old = chunk[pos]
				local new = updateFunc(i, old)
				chunk[pos] = new

				if old == nil then
					if new ~= nil then
						self._count += 1
					end
				elseif new == nil then
					self._count -= 1
				end
			end
		end

		-- Advance to the first stepped index at or beyond the next chunk
		local advanced = chunkEnd - start
		index = start + (advanced // step + 1) * step
	end
end


-- non-nil elements
function InfArray.Count(self: InfArray): number
	return self._count
end


-- Highest assigned index
function InfArray.Length(self: InfArray): number
	return self._length
end

-- `#arr` is the highest assigned index
function InfArray.__len(self: InfArray): number
	return self._length
end

-- Backwards-compatible aliases
InfArray.get = InfArray.Get
InfArray.set = InfArray.Set
InfArray.GetValueAtIndex = InfArray.Get
InfArray.Replace = InfArray.Set
InfArray.InsertBack = InfArray.PushBack
InfArray.TransformRange = InfArray.Transform
InfArray.GetTotalLen = InfArray.Count
InfArray.GetLength = InfArray.Length

return InfArray
