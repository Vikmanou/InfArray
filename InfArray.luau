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


--[=[
	@class InfArray

	A chunked array that bypasses Luau's internal table size limit of 2^26.

	Values are stored across fixed-size chunks so a single logical array can hold
	up to 2^53 elements (the largest exact integer a Luau `number` can represent).
	Indices are 1-based and resolved with integer math.

	Removals leave `nil` holes. Per-chunk logical lengths are tracked explicitly, so
	the implementation never relies on `#` over a chunk (which is undefined once the
	chunk contains holes). [InfArray:Length] reports the highest assigned index
	(holes included), while [InfArray:Count] reports the number of present elements.

	```lua
	local InfArray = require(path.to.InfArray)

	local arr = InfArray.new()
	arr:PushBack("a")
	arr:PushBack("b")
	print(arr:Get(1)) --> "a"
	print(#arr)       --> 2
	```

	Several backwards-compatible aliases exist for the primary methods:
	`get`/`GetValueAtIndex` (Get), `set`/`Replace` (Set), `InsertBack` (PushBack),
	`TransformRange` (Transform), `GetTotalLen` (Count) and `GetLength` (Length).
]=]
local InfArray = { LIMIT = LIMIT, locate = locateWithIndex }
InfArray.__index = InfArray

--[=[
	@within InfArray
	@prop LIMIT number
	@readonly
	@tag static

	Maximum number of elements a single chunk can hold (2^26 = 67108864).
]=]

--[=[
	@within InfArray
	@function new
	@param size number? -- Optional initial length; pre-allocates chunks.
	@param value any? -- Optional fill value written to every pre-allocated slot.
	@return InfArray

	Creates a new [InfArray]. When `size` is given, the array is pre-sized to `size`
	elements; if `value` is also provided, every slot is filled with it and
	[InfArray:Count] reflects the full size (otherwise the slots start as holes).
]=]
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


--[=[
	@within InfArray
	@method Get
	@param index number -- 1-based global index.
	@return any? -- The value at `index`, or `nil` if unset or out of range.

	Reads the value at `index` in O(1). Returns `nil` for holes and for indices
	whose chunk does not exist yet.
]=]
function InfArray.Get(self: InfArray, index: number): any?
	local chunkIndex, pos = locateWithIndex(index)
	local chunk = self._chunks[chunkIndex]
	return chunk and chunk[pos]
end


--[=[
	@within InfArray
	@method Set
	@param index number -- 1-based global index within an existing chunk.
	@param value any? -- New value; pass `nil` to clear the slot into a hole.

	In-range O(1) write that keeps [InfArray:Count] and [InfArray:Length] correct.
	This is a **no-op** if the index's chunk does not exist yet — use
	[InfArray:PushBack], [InfArray.new] with a size, or [InfArray:SetChunk] to grow
	the array first.
]=]
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


--[=[
	@within InfArray
	@method GetChunk
	@param index number -- 1-based chunk index.
	@return {any}? -- The raw backing table for that chunk, or `nil`.

	Returns the raw chunk table by chunk index. The returned table may contain
	`nil` holes and is not length-safe under `#`; pair it with the chunk's tracked
	length (see [InfArray:IterateChunks]) when scanning it.
]=]
function InfArray.GetChunk(self: InfArray, index: number): Chunk?
	return self._chunks[index]
end


--[=[
	@within InfArray
	@method SetChunk
	@param chunkIndex number -- 1-based chunk index to replace.
	@param value {any} -- The new backing table for the chunk.
	@param len number? -- Logical length of `value`; defaults to `#value`.

	Replaces an entire chunk in one call, recomputing [InfArray:Count] for the
	swapped range and extending [InfArray:Length] if the new chunk reaches further.
	Prefer this over per-element writes for bulk population.
]=]
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


--[=[
	@within InfArray
	@method GetChunkAndPosition
	@param index number -- 1-based global index.
	@return {any}? -- The chunk containing `index`, or `nil` if absent.
	@return number -- The 1-based position of `index` within that chunk.

	Resolves a global index to its chunk and in-chunk position in one call, useful
	for hot loops that want to read/write a slot without recomputing the location.
]=]
function InfArray.GetChunkAndPosition(self: InfArray, index: number): (Chunk?, number)
	local chunkIndex, pos = locateWithIndex(index)
	return self._chunks[chunkIndex], pos
end


--[=[
	@within InfArray
	@method PushBack
	@param value any -- Value to append at the end of the array.
	@return number -- The global index the value was written to.

	Appends `value` after the highest assigned index, allocating a new chunk when
	the current one fills up. Amortised O(1).
]=]
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

--[=[
	@within InfArray
	@method RemoveIndex
	@param index number -- 1-based global index to clear.

	Clears the value at `index`, decrementing [InfArray:Count]. This leaves a `nil`
	hole — [InfArray:Length] is **unchanged** and later elements are not shifted.
]=]
function InfArray.RemoveIndex(self: InfArray, index: number)
	local chunkIndex, pos = locateWithIndex(index)
	local chunk = self._chunks[chunkIndex]
	if not chunk then return end

	if chunk[pos] ~= nil then
		chunk[pos] = nil
		self._count -= 1
	end
end

--[=[
	@within InfArray
	@method __iter
	@ignore

	Generalized `for..in` iteration (`for index, value in arr do`). Holes are
	skipped. Prefer [InfArray:IterateChunks] for bulk throughput.
]=]
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

--[=[
	@within InfArray
	@method Iterate
	@param callback (index: number, value: any) -> boolean? -- Called for each present element; return `true` to stop early.

	Iterates every present element in ascending index order, skipping holes. Return
	`true` from `callback` to break out early. For maximum bulk throughput, use
	[InfArray:IterateChunks] instead.
]=]
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

--[=[
	@within InfArray
	@method IterateChunks
	@param callback (chunk: {any}, base: number, len: number) -> boolean? -- Called once per chunk; return `true` to stop early.

	Hands each raw chunk to `callback` along with its `base` global-index offset and
	tracked `len`. The fastest way to process the whole array in bulk. The caller
	**must** nil-check `chunk[j]` itself, since chunks may contain holes. Return
	`true` to stop early.
]=]
function InfArray.IterateChunks(self: InfArray, callback: (chunk: Chunk, base: number, len: number) -> boolean?)
	local chunks, lens = self._chunks, self._lens

	for i = 1, #chunks do
		if callback(chunks[i], (i - 1) * LIMIT, lens[i]) then
			return
		end
	end
end

--[=[
	@within InfArray
	@method Find
	@param needle any -- Value to search for.
	@return number? -- The first global index equal to `needle`, or `nil`.

	Linearly scans in ascending order and returns the first global index whose value
	equals `needle`, or `nil` if not found. Scans to each chunk's tracked length so
	holes never cut the search short.
]=]
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

--[=[
	@within InfArray
	@method Transform
	@param start number -- First global index to visit (inclusive).
	@param stop number -- Last global index to visit (inclusive).
	@param step number -- Stride between visited indices.
	@param updateFunc (index: number, value: any) -> any -- Returns the new value for each visited slot.

	Applies `updateFunc` over the range `[start, stop]` by `step`, writing back each
	returned value. May turn holes into values (or values back into holes);
	[InfArray:Count] stays correct either way. Indices whose chunk does not exist
	are skipped.
]=]
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


--[=[
	@within InfArray
	@method Count
	@return number -- The number of present (non-`nil`) elements.

	Returns how many elements are actually present, excluding holes. O(1).
]=]
function InfArray.Count(self: InfArray): number
	return self._count
end


--[=[
	@within InfArray
	@method Length
	@return number -- The highest assigned index (holes included).

	Returns the logical length: the highest index ever assigned, counting holes.
	Equivalent to `#arr`. O(1).
]=]
function InfArray.Length(self: InfArray): number
	return self._length
end

--[=[
	@within InfArray
	@method __len
	@ignore

	`#arr` returns the highest assigned index. See [InfArray:Length].
]=]
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
