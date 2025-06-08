--!native

--[[

    InfArray.lua
    Syveric


    Bypass Luau's internal table size limitation of 2^26 (approximately 67 million elements).

    InfArray achieves this by chunking data into smaller segments.
]]

--[[
	Reference:
	Luau source (ltable.cpp):
	https://github.com/luau-lang/luau/blob/master/VM/src/ltable.cpp

	Lines 36–38:
		// max size of both array and hash part is 2^MAXBITS
		#define MAXBITS 26
		#define MAXSIZE (1 << MAXBITS)
]]
local LIMIT_BITS = 26
local LIMIT = bit32.lshift(1, LIMIT_BITS)
local LIMIT_MASK = LIMIT - 1 -- For faster modulo operations

type InfArray = typeof(setmetatable({} :: any, {} :: any))

local InfArray = {LIMIT = LIMIT} do
	InfArray.__index = InfArray

	function InfArray.new(size: number?, value: any?): InfArray
		local self = setmetatable({}, InfArray)

		self._chunks = {}
		self._count = 0

		if size then
			local chunkCount = math.ceil(size / LIMIT)

			for i = 1, chunkCount do
				local chunkSize = (i < chunkCount or size % LIMIT == 0) and LIMIT or (size % LIMIT)
				self:SetChunk(i, table.create(chunkSize, value))
			end
		end

		return self
	end


	function InfArray:GetChunk(index: number): { any? }?
		return self._chunks[index]
	end


	function InfArray:SetChunk(chunk: number, value: { any? })
		local oldChunkCount = self._chunks[chunk] and #self._chunks[chunk] or 0
		self._count += #value - oldChunkCount
		self._chunks[chunk] = value
	end


	function InfArray:Iterate(callback: (index: number, value: any) -> (boolean?))
		for i = 1, #self._chunks do
			local chunk = self._chunks[i]
			local chunkStartPos = bit32.lshift(i - 1, LIMIT_BITS)

			for j = 1, #chunk do
				local value = chunk[j]
				if value ~= nil then
					local shouldStop = callback(chunkStartPos + j, value)

					if shouldStop then
						return
					end
				end
			end
		end
	end


	function InfArray:GetChunkAndPosition(index: number): ({any}?, number)
		local chunkIndex = bit32.rshift(index + LIMIT - 1, LIMIT_BITS)
		local posInChunk = bit32.band(index - 1, LIMIT_MASK) + 1

		return self._chunks[chunkIndex], posInChunk
	end


	function InfArray:ParallelTransform(processFunc: (value: any) -> any, threadCount: number?)
		local threads = math.max(2, threadCount or 1)

		local completedThreads = 0
		local processingComplete = false
		local processingCompleteEvent = Instance.new('BindableEvent')

		for threadId = 1, threads do
			task.spawn(function()
				local startChunk = (threadId - 1) * math.ceil(#self._chunks / threads) + 1
				local endChunk = math.min(threadId * math.ceil(#self._chunks / threads), #self._chunks)

				for i = startChunk, endChunk do
					local chunk = self._chunks[i]

					-- Process each element in the chunk
					for j = 1, #chunk do
						local index = bit32.lshift(i - 1, LIMIT_BITS) + j
						chunk[j] = processFunc(index, chunk[j])
					end
				end

				completedThreads += 1
				if completedThreads >= threads then
					processingComplete = true
					processingCompleteEvent:Fire()
				end
			end)
		end

		if not processingComplete then
			processingCompleteEvent.Event:Wait()
		end
	end


	function InfArray:Find(value: any): number?
		for i = 1, #self._chunks do
			local valIdx = table.find(self._chunks[i], value)
			if valIdx then
				return valIdx + bit32.lshift(i - 1, LIMIT_BITS)
			end
		end

		return nil
	end


	function InfArray:GetValueAtIndex(index: number): any?
		local chunkIndex = bit32.rshift(index + LIMIT - 1, LIMIT_BITS)

		local chunk = self._chunks[chunkIndex]

		if not chunk then return nil end

		local posInChunk = bit32.band(index - 1, LIMIT_MASK) + 1
		return chunk[posInChunk]
	end


	function InfArray:InsertBack(value: any)
		local chunksLen = #self._chunks

		local insertChunk = chunksLen > 0 and self._chunks[chunksLen] or nil
		local insertChunkLen = insertChunk and #insertChunk or 0

		if not (insertChunk and insertChunkLen < LIMIT) then
			local newChunk = table.create(math.min(2^16, LIMIT), nil) -- magical
			self:SetChunk(chunksLen + 1, newChunk)
			insertChunk = newChunk
			insertChunkLen = 0
		end

		insertChunk[insertChunkLen + 1] = value

		self._count += 1
	end


	function InfArray:RemoveIndex(index: number)
		local chunk, posInChunk = self:GetChunkAndPosition(index)
		if not chunk then return end

		local oldValue = chunk[posInChunk]
		chunk[posInChunk] = nil

		if oldValue ~= nil then
			self._count -= 1
		end
	end


	function InfArray:TransformRange(start: number, endValue: number, step: number, updateFunc: (value: any, index: number) -> any)
		local startChunkIndex = bit32.rshift(start + LIMIT - 1, LIMIT_BITS)
		local endChunkIndex = bit32.rshift(endValue + LIMIT - 1, LIMIT_BITS)

		-- Process first chunk (special case for starting position)
		local chunk = self._chunks[startChunkIndex]
		if chunk then
			local chunkStartPos = bit32.lshift(startChunkIndex - 1, LIMIT_BITS)
			for index = start, math.min(chunkStartPos + LIMIT - 1, endValue), step do
				local posInChunk = bit32.band(index - 1, LIMIT_MASK) + 1
				chunk[posInChunk] = updateFunc(index, chunk[posInChunk])
			end
		end

		-- Process middle chunks (full chunks)
		for chunkIndex = startChunkIndex + 1, endChunkIndex - 1 do
			chunk = self._chunks[chunkIndex]
			if not chunk then continue end

			local chunkStartPos = bit32.lshift(chunkIndex - 1, LIMIT_BITS)

			local firstStepElement = chunkStartPos + 1
			local offset = (firstStepElement - start) % step
			if offset ~= 0 then
				firstStepElement = firstStepElement + (step - offset)
			end

			for index = firstStepElement, chunkStartPos + LIMIT - 1, step do
				if index > endValue then break end
				local posInChunk = bit32.band(index - 1, LIMIT_MASK) + 1
				chunk[posInChunk] = updateFunc(index, chunk[posInChunk])
			end
		end

		-- Process last chunk (may be partial)
		if startChunkIndex ~= endChunkIndex then
			chunk = self._chunks[endChunkIndex]
			if chunk then
				local chunkStartPos = bit32.lshift(endChunkIndex - 1, LIMIT_BITS)

				local firstStepElement = chunkStartPos + 1
				local offset = (firstStepElement - start) % step
				if offset ~= 0 then
					firstStepElement = firstStepElement + (step - offset)
				end

				for index = firstStepElement, endValue, step do
					local posInChunk = bit32.band(index - 1, LIMIT_MASK) + 1
					chunk[posInChunk] = updateFunc(index, chunk[posInChunk])
				end
			end
		end
	end


	function InfArray:Replace(index: number, newValue: any)
		local chunk, posInChunk = self:GetChunkAndPosition(index)
		if not chunk then return end
		chunk[posInChunk] = newValue
	end


	function InfArray:GetTotalLen(): number
		return self._count
	end
end


return InfArray