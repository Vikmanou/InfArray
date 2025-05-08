--[[

	InfTable.lua
	Syveric

	A module used to store table larger than Roblox Luau's (or C's) table limit

	Example:

		local tableName = InfTable.new('index')

		-- populate the table
		local i, limit = 0, 30
		while i < limit do
			i += 1
			t:Add({i, i*2})
		end

		t:Iterate(function(index: number, value: any, chunk: { any }): boolean
			if value == 4 then
				print('a', index)
				return true
			end
		end)

		print(t:GetValueAtIndex(5))
		t:RemoveIndex(5)
		print(t:GetValueAtIndex(5))

	--



]]

local LIMIT = bit32.lshift(1, 26) -- Luau source code (ltable.cpp): #define MAXBITS 26 #define MAXSIZE (1 << MAXBITS)


export type InfTableObject = {
	_type: string?,
	_chunks: { { any } },

	GetChunk: (number) -> { any }?,
	SetChunk: (number, { any? }) -> (),
	GetTotalElementLen: () -> (),
	Iterate: ((number, any, { any }) -> any) -> (any?),
	Find: (any) -> (number?, number, number?),
	GetValueAtIndex: (number) -> (any?, number?, number?),
	Add: (any, any?) -> (),
	Replace: (number, any) -> ()
}


local InfArray = {} do
	InfArray.__index = InfArray

	function InfArray.new(size: number?, value: any?)
		local self = setmetatable({}, InfArray)

		self._chunks = {}
		self._count = 0

		if size then
			local chunkCount = math.ceil(size / LIMIT)
			for i = 1, chunkCount do
				self:SetChunk(i, table.create(LIMIT, value))
			end
		end

		return self
	end

	function InfArray:GetChunk(index: number): { any }?
		return self._chunks[index]
	end

	function InfArray:SetChunk(chunk: number, value: { any? })
		local oldChunkCount = self._chunks[chunk] and #self._chunks[chunk] or 0
		self._count += #value - oldChunkCount
		self._chunks[chunk] = value
	end

	function InfArray:GetTotalLen(): number
		return self._count
	end

	function InfArray:Iterate(callback: (index: number, value: any) -> nil)
		for i = 1, #self._chunks do
			local chunk = self._chunks[i]

			for j = 1, #chunk do
				callback(j, chunk[j])
			end
		end
	end

	function InfArray:Find(value: any): number?
		for i = 1, #self._chunks do
			local chunk = self._chunks[i]

			for j = 1, #chunk do
				if chunk[j] == value then
					return j + (i - 1) * LIMIT
				end
			end
		end

        return nil
	end

	function InfArray:GetValueAtIndex(index: number): any?
		local chunkIndex = math.ceil(index / LIMIT)
		local chunk = self._chunks[chunkIndex]

		if not chunk then return nil, nil, nil end

		local indexInChunk = index - (chunkIndex - 1) * LIMIT
		return chunk[indexInChunk]
	end

	function InfArray:InsertBack(value: any)
		local insertChunk = self._chunks[#self._chunks]
		if not (insertChunk and #insertChunk < LIMIT) then
			self:SetChunk(#self._chunks + 1, table.create(LIMIT, nil))
			insertChunk = self._chunks[#self._chunks]
		end

		insertChunk[#insertChunk + 1] = value

		self._count += 1
	end

	function InfArray:RemoveIndex(index: number)
		local chunkIndex = math.ceil(index / LIMIT)
		local chunk = self._chunks[chunkIndex]

		if not chunk then return end

		local indexInChunk = index - (chunkIndex - 1) * LIMIT
		chunk[indexInChunk] = nil

		if next(chunk) == nil then
			self._chunks[chunkIndex] = nil
			self._count -= LIMIT
		end
	end

	function InfArray:Replace(index: number, newValue: any)
		local chunkIndex = math.ceil(index / LIMIT)
		local chunk = self._chunks[chunkIndex]

		if not chunk then return end

		local indexInChunk = index - (chunkIndex - 1) * LIMIT
		chunk[indexInChunk] = newValue
	end
end


--[=[]]
function module.new(tableType: 'index' | 'dict', count: number?, value: any?)
	local InfTable = {
		_type = tableType or 'dict', -- assuming it is a dictionnary as default
		_chunks = {}
	}



	function InfTable:GetChunk(index: number)
		return self._chunks[index]
	end


	function InfTable:SetChunk(chunk, value)
		self._chunks[chunk] = value
	end


	function InfTable:GetTotalElementLen()
		local i, res = 1, 0

		while self._chunks[i] ~= nil do
			res += self._type == 'index' and #self._chunks[i] or countInDict(self._chunks[i])
			i += 1
		end

		return res
	end


	function InfTable:Iterate(predicate: (index: any, value: any, chunk: { any }) -> any?): any?
		local finish = false

		local i = 1
		while self._chunks[i] and not finish do
			local chunk = self._chunks[i]

			if self._type == 'index' then
				for j = 1, #chunk do
					local predicateAnswer = predicate(j, chunk[j], chunk)
					if predicateAnswer then
						return predicateAnswer
					end
				end
			else
				for k, v in pairs(chunk) do
					local predicateAnswer = predicate(k, v, chunk)
					if predicateAnswer then
						return predicateAnswer
					end
				end
			end

			i += 1
		end

        return nil
	end


	function InfTable:Find(value)
		local i, items = 1, 0
		while self._chunks[i] do
			local chunk = self._chunks[i]
			local chunkLen

			if self._type == 'index' then
				chunkLen = #chunk
				for j = 1, chunkLen do
					if chunk[j] == value then return j, items+j, i end
				end
			else
				chunkLen = countInDict(chunk)
				for k, v in pairs(chunk) do
					if v == value then return k, items+k, i end
				end
			end

			i += 1
			items += chunkLen
		end
	end


	function InfTable:GetValueAtIndex(index)
		local i, items = 1, 0
		while self._chunks[i] do
			local chunk = self._chunks[i]
			local chunkLen

			if self._type == 'index' then
				chunkLen = #chunk
				if items+chunkLen >= index then
					return chunk[index-items], i, index-items
				end
			else
				chunkLen = countInDict(chunk)
				if chunk[index] then return chunk[index], i, index end
			end

			items += chunkLen
			i += 1
		end
	end


	function InfTable:Add(indexOrValue, value)
		if indexOrValue == nil then
			return warn('InfTable -> Can not insert nil for index nor value')
		end

		local cost = 1

		local i = 0
		while true do
			i += 1

			local chunk = self._chunks[i]
			if not chunk then
				if self._type == 'index' then self._chunks[i] = { indexOrValue }
				else self._chunks[i] = { [indexOrValue] = value }
				end

				break
			end

			-- No space in this chunk
			local chunkLen = self._type == 'index' and #chunk or countInDict(chunk)
			if LIMIT - chunkLen <= cost then continue end

			if self._type == 'index' then table.insert(chunk, indexOrValue) print('ins')
			else chunk[indexOrValue] = value
			end

			break
		end
	end


	function InfTable:RemoveIndex(index)
		if index == nil then
			return warn('InfTable -> Unknown index to remove')
		end

		local value, chunkn, chunkIndex = self:GetValueAtIndex(index)
		if not value then return end

		local chunk = self._chunks[chunkn]
		if not chunk then return end

		chunk[self._type == 'index' and chunkIndex or index] = nil

		if next(chunk) == nil or countInDict(chunk) == 0 then
			self._chunks[chunkn] = nil

			-- Push down subsequent chunks to fill the whole
			local n = 1
			while self._chunks[chunkn+n] do
				local chunk = self._chunks[chunkn+n]

				-- Move chunk down
				self._chunks[chunkn+n-1] = chunk
				self._chunks[chunkn+n] = nil

				n += 1
			end
		elseif self._type == 'index' then
			-- fill in empty gaps in table
			for i = chunkIndex, #chunk do
				chunk[i] = chunk[i+1]
			end
		end
	end

	function InfTable:Replace(index, newValue)
		if newValue == nil then
			return self:RemoveIndex(index)
		end

		local value, chunkn, chunkIndex = self:GetValueAtIndex(index)
		if not value then return end

		local chunk = self._chunks[chunkn]
		if not chunk then return end

		chunk[chunkIndex] = newValue
	end

	return InfTable :: InfTableObject
end
]=]

return InfArray