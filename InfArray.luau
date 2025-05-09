--[[

	InfArray.lua
	Syveric


	Bypass Luau's internal table size limitation of 2^26 (approximately 67 million elements).
	
	InfArray achieves this by chunking data into smaller segments.
	
	Useful for handling massive datasets that demand storage exceeding the built-in constraints of Luau.


	Usage Example:

		local InfArr = require(game.ReplicatedStorage.Utility.InfTable:Clone())


		local t = InfArr.new(10)

		local limit = 30

		print(t:GetTotalLen())
		print(t:GetValueAtIndex(5))

		local i = 0
		while i < limit do
			i += 1
			t:InsertBack(i)
		end

		t:Iterate(function(index: number, value: any)
			print(index, value)
		end)

		print(t:Find(8))
		print(t:GetTotalLen())
		print(t:GetValueAtIndex(5))
		t:Replace(5, 'replace thing')
		print(t:GetValueAtIndex(5))
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
local LIMIT = bit32.lshift(1, 26)

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
				self:SetChunk(i, table.create(LIMIT, value))
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
	

	@native function InfArray:Iterate(callback: (index: number, value: any) -> ())
		for i = 1, #self._chunks do
			local chunk = self._chunks[i]

			local chunkStartPos = (i - 1) * LIMIT
			for j = 1, #chunk do
				callback(chunkStartPos + j, chunk[j])
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


	@native function InfArray:GetValueAtIndex(index: number): any?
		local chunkIndex = math.ceil(index / LIMIT)
		local chunk = self._chunks[chunkIndex]

		if not chunk then return nil end

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
		
		local oldValue = chunk[indexInChunk]
		chunk[indexInChunk] = nil

		-- Cleanup chunk if empty?

		if oldValue ~= nil then
			self._count -= 1
		end
	end
	

	@native function InfArray:Replace(index: number, newValue: any)
		local chunkIndex = math.ceil(index / LIMIT)
		local chunk = self._chunks[chunkIndex]

		if not chunk then return end

		local indexInChunk = index - (chunkIndex - 1) * LIMIT
		chunk[indexInChunk] = newValue
	end
	
	
	function InfArray:GetTotalLen(): number
		return self._count
	end
end


return InfArray