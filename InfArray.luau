--!native
--!optimize 2

--[[

    InfArray.luau
    Viken (@Syveric on Roblox)

    Bypass Luau's internal table size limit of 2^26
    by chunking values into segments. Indices use integer math, so
    the array is valid up to 2^53, the largest exact integer a Luau number holds.

    A cleared slot stores the private EMPTY tombstone rather than nil, so a chunk
    is never a holey table. Scans stay on Luau's array fast paths no matter how
    the array has been mutated: Find is always a single table.find fastcall and
    a chunk never spills slots into the table's hash part.

        Length() -- highest assigned index, holes included.
        Count()  -- number of present (non-nil) elements.
]]

-- Luau caps the array length at 2^MAXBITS, MAXBITS = 26.
-- See ltable.cpp: https://github.com/luau-lang/luau/blob/master/VM/src/ltable.cpp
local LIMIT_BITS = 26
local LIMIT = 2 ^ LIMIT_BITS -- 67108864 elements per chunk

local APPEND_PREALLOC = math.min(2 ^ 16, LIMIT)

local EMPTY = table.freeze({})

type Chunk = { any }

export type InfArray = typeof(setmetatable(
	{} :: {
		_chunks: { Chunk },
		_lens: { number }, -- length per chunk, holes included
		_holes: { number }, -- tombstoned slots per chunk, within its length
		_length: number, -- length of the whole array, holes included
		_count: number, -- number of present (non nil) elements
	},
	{} :: { __index: any }
))


--[=[
	@class InfArray

	A chunked array that bypasses Luau's internal table size limit of 2^26.

	Values are stored across fixed-size chunks so a single logical array can hold
	up to 2^53 elements (the largest exact integer a Luau `number` can represent).
	Indices are 1-based and resolved with integer math.

	Removals leave holes. [InfArray:Length] reports the highest assigned index
	(holes included), while [InfArray:Count] reports the number of present
	elements. A hole reads back as `nil` through [InfArray:Get] and is skipped by
	iteration, but the backing slot holds the [InfArray.EMPTY] tombstone, so raw
	chunks are dense tables rather than holey ones.

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
local InfArray = { LIMIT = LIMIT, EMPTY = EMPTY }
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
	@prop EMPTY any
	@readonly
	@tag static

	Marks a hole in a raw chunk.

	**Use `EMPTY` only when you index a chunk table yourself. Everywhere else use
	`nil`.** The three functions that hand back a raw chunk are
	[InfArray:GetChunk], [InfArray:GetChunkAndPosition] and
	[InfArray:IterateChunks].
	
	| Doing | Use |
	| --- | --- |
	| `Set(i, nil)`, `PushBack(nil)`, `Transform` returning nil | `nil` |
	| A table with gaps passed to [InfArray:SetChunk] | `nil`, rewritten for you |
	| Reading [InfArray:Get] | `nil` |
	| [InfArray:Transform] callback's value argument | `nil` |
	| [InfArray:Iterate] or `for..in` value | neither, holes are skipped |
	| `chunk[j]` from a raw chunk | `EMPTY` |

	Inside a chunk's tracked length a slot is a value or `EMPTY`, never `nil`.
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
		_holes = {},
		_length = 0,
		_count = 0
	}, InfArray)

	if size and size > 0 then
		local chunkCount = (size - 1) // LIMIT + 1
		local chunks, lens, holes = self._chunks, self._lens, self._holes
		local filled = value ~= nil
		local stored = if filled then value else EMPTY

		for i = 1, chunkCount do
			local chunkSize = if i < chunkCount then LIMIT else size - (chunkCount - 1) * LIMIT
			chunks[i] = table.create(chunkSize, stored)
			lens[i] = chunkSize
			holes[i] = if filled then 0 else chunkSize
		end

		self._length = size
		self._count = if filled then size else 0
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
	local i = index - 1
	local chunkIndex = i // LIMIT
	local chunk = self._chunks[chunkIndex + 1]
	if chunk == nil then return nil end

	local value = chunk[i - chunkIndex * LIMIT + 1]
	if value == EMPTY then return nil end
	return value
end


--[=[
	@within InfArray
	@method Set
	@param index number -- 1-based global index within an existing chunk.
	@param value any? -- New value; pass `nil` to clear the slot into a hole.
	@return boolean -- `true` if the write happened, `false` if it was a no-op.

	In-range O(1) write that keeps [InfArray:Count] and [InfArray:Length] correct.
	Returns `true` when the write lands. This is a **no-op** returning `false` if
	the index's chunk does not exist yet — use [InfArray:PushBack],
	[InfArray.new] with a size, or [InfArray:SetChunk] to grow the array first.

	Writing past the chunk's current length extends it and tombstones the skipped
	slots, which costs O(gap).
]=]
function InfArray.Set(self: InfArray, index: number, value: any?): boolean
	local i = index - 1
	local chunkIndex = i // LIMIT
	local base = chunkIndex * LIMIT
	local pos = i - base + 1
	chunkIndex += 1

	local chunk = self._chunks[chunkIndex]
	if not chunk then return false end

	local holes = self._holes
	local old = chunk[pos]

	if value ~= nil then
		local lens = self._lens
		local len = lens[chunkIndex]

		if pos > len then
			local carried = 0
			for j = len + 1, pos - 1 do
				local slot = chunk[j]
				if slot == nil then
					chunk[j] = EMPTY
				elseif slot ~= EMPTY then
					carried += 1
				end
			end

			holes[chunkIndex] += pos - 1 - len - carried
			lens[chunkIndex] = pos

			local logical = base + pos
			if logical > self._length then
				self._length = logical
			end
		end

		chunk[pos] = value

		if old == EMPTY then
			holes[chunkIndex] -= 1
			self._count += 1
		elseif old == nil then
			self._count += 1
		end
	else
		chunk[pos] = EMPTY

		if old ~= nil and old ~= EMPTY then
			self._count -= 1
			holes[chunkIndex] += 1
		end
	end

	return true
end


--[=[
	@within InfArray
	@method GetChunk
	@param index number -- 1-based chunk index.
	@return {any}? -- The raw backing table for that chunk, or `nil`.

	Returns the raw chunk table by chunk index. Cleared slots hold
	[InfArray.EMPTY], not `nil`, and the table is padded past its logical length;
	pair it with the chunk's tracked length (see [InfArray:IterateChunks]) when
	scanning it.
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

	Takes ownership of `value`: any `nil` below the chunk's length is rewritten in
	place as an [InfArray.EMPTY] tombstone.
]=]
function InfArray.SetChunk(self: InfArray, chunkIndex: number, value: Chunk, len: number?)
	local lens, holes = self._lens, self._holes
	local base = (chunkIndex - 1) * LIMIT

	local oldLen = lens[chunkIndex]
	if oldLen then
		self._count -= oldLen - holes[chunkIndex]
	end

	local newLen = len or #value

	local covered = self._length - base
	if covered > LIMIT then
		covered = LIMIT
	end
	if covered > newLen then
		newLen = covered
	end

	local newHoles = 0
	for i = 1, newLen do
		local slot = value[i]
		if slot == nil then
			value[i] = EMPTY
			newHoles += 1
		elseif slot == EMPTY then
			newHoles += 1
		end
	end

	self._count += newLen - newHoles
	holes[chunkIndex] = newHoles
	lens[chunkIndex] = newLen
	self._chunks[chunkIndex] = value

	local logical = base + newLen
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
	local i = index - 1
	local chunkIndex = i // LIMIT
	return self._chunks[chunkIndex + 1], i - chunkIndex * LIMIT + 1
end


--[=[
	@within InfArray
	@method PushBack
	@param value any -- Value to append at the end of the array.
	@return number -- The global index the value was written to.

	Appends `value` after the highest assigned index, allocating a new chunk when
	the current one fills up. Amortised O(1). Appending `nil` extends
	[InfArray:Length] with a hole and leaves [InfArray:Count] unchanged.
]=]
function InfArray.PushBack(self: InfArray, value: any): number
	local index = self._length + 1
	local i = index - 1
	local chunkIndex = i // LIMIT
	local pos = i - chunkIndex * LIMIT + 1
	chunkIndex += 1

	local chunks = self._chunks
	local chunk = chunks[chunkIndex]
	if not chunk then
		chunk = table.create(APPEND_PREALLOC)
		chunks[chunkIndex] = chunk
		self._holes[chunkIndex] = 0
	end

	if value == nil then
		value = EMPTY
		self._holes[chunkIndex] += 1
	else
		self._count += 1
	end

	chunk[pos] = value
	self._lens[chunkIndex] = pos
	self._length = index

	return index
end

--[=[
	@within InfArray
	@method RemoveIndex
	@param index number -- 1-based global index to clear.

	Clears the value at `index`, decrementing [InfArray:Count]. This leaves a hole.
	[InfArray:Length] is **unchanged** and later elements are not shifted.
]=]
function InfArray.RemoveIndex(self: InfArray, index: number)
	local i = index - 1
	local chunkIndex = i // LIMIT
	local pos = i - chunkIndex * LIMIT + 1
	chunkIndex += 1

	local chunk = self._chunks[chunkIndex]
	if not chunk then return end

	local old = chunk[pos]
	if old ~= nil and old ~= EMPTY then
		chunk[pos] = EMPTY
		self._count -= 1

		if pos <= self._lens[chunkIndex] then
			self._holes[chunkIndex] += 1
		end
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
			if value ~= EMPTY then
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
	local chunks, lens, holes = self._chunks, self._lens, self._holes

	for i = 1, #chunks do
		local chunk = chunks[i]
		local len = lens[i]
		local base = (i - 1) * LIMIT

		if holes[i] == 0 then
			for j = 1, len do
				if callback(base + j, chunk[j]) then
					return
				end
			end
		else
			for j = 1, len do
				local value = chunk[j]
				if value ~= EMPTY then
					if callback(base + j, value) then
						return
					end
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
	**must** skip slots equal to [InfArray.EMPTY] itself, since chunks tombstone
	their holes. Return `true` to stop early.
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
	equals `needle`, or `nil` if not found. Holes never cut the search short, and
	searching for `nil` always returns `nil`. Pass [InfArray.EMPTY] to locate the
	first hole.
]=]
function InfArray.Find(self: InfArray, needle: any): number?
	if needle == nil then return nil end

	local chunks, lens = self._chunks, self._lens

	for i = 1, #chunks do
		local hit = table.find(chunks[i], needle)
		if hit and hit <= lens[i] then
			return (i - 1) * LIMIT + hit
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
	returned value. `updateFunc` sees `nil` for a hole and may return `nil` to clear
	a slot; [InfArray:Count] stays correct either way. Indices whose chunk does not
	exist are skipped.
]=]
function InfArray.Transform(
	self: InfArray,
	start: number,
	stop: number,
	step: number,
	updateFunc: (index: number, value: any) -> any
)
	local chunks, holes = self._chunks, self._holes

	local index = start
	while index <= stop do
		local chunkIndex = (index - 1) // LIMIT
		local base = chunkIndex * LIMIT
		local chunkEnd = base + LIMIT
		chunkIndex += 1

		local chunk = chunks[chunkIndex]
		if chunk then
			local limit = math.min(chunkEnd, stop)
			local delta = 0
			local holeDelta = 0

			for i = index, limit, step do
				local pos = i - base
				local raw = chunk[pos]
				local new = updateFunc(i, if raw ~= EMPTY then raw else nil)

				if new ~= nil then
					chunk[pos] = new

					if raw == EMPTY then
						delta += 1
						holeDelta -= 1
					elseif raw == nil then
						delta += 1
					end
				else
					chunk[pos] = EMPTY

					if raw ~= nil and raw ~= EMPTY then
						delta -= 1
						holeDelta += 1
					end
				end
			end

			if delta ~= 0 then
				self._count += delta
			end

			if holeDelta ~= 0 then
				holes[chunkIndex] += holeDelta
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
