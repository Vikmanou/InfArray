# InfArray

InfArray is a library that bypasses Luau's internal table size limitation of 2^26 by chunking data into smaller segments.
Useful for handling massive datasets that demand storage exceeding the built-in constraints of Luau.

### InfArray.new([size: number], [value: any]) (Constructor)

Creates a new InfArray instance. Read limitations for arrays larger than 2^24.
* `size` (optional): Pre-allocates space for the specified number of elements.
* `value` (optional): Initializes all elements with this value (most efficient with numeric values).

### API

| Method Name | Description | Argument(s) | Return Value(s) | Time Complexity |
| ----------- | ----------- | ------------- | ---------------- | --------------- |
| `GetChunk` | Returns the chunk at the specified index. | `chunkIndex: number` | `{ any }?` | `O(1)`
| `SetChunk` | Sets the chunk at the specified index | `chunkIndex: number, value: { any }` | `nil` | `O(1)`
| `GetTotalLen` | Returns the amount of elements in the InfArray | `nil` | `number` | `O(1)`
| `Iterate` | Iterate through the InfArray | `callback: ((index: number, value: any) -> any?)` | `nil` | `O(n)`
| `Find` | Goes through the table and finds this value | `value: any` | `indexInChunk: number?, indexInTable: number, chunkIndex: number?` | `O(n)`
| `GetValueAtIndex` | Gets the value at specified index | `index: number` | `valueInChunk: any?, chunkIndex: number?, yourIndex: number?` | `O(1)`
| `InsertBack` | Add element to table | `value: any` | `nil` | `O(1)`
| `RemoveIndex` | Remove index from table | `index: number` | `nil` | `O(1)`
| `Replace` | Replace index in table | `index: number, newValue: any` | `nil` | `O(1)`
| `ParallelTransform` | Process all elements in parallel | `processFunc: (index: number, value: any) -> any, threadCount: number?` | `nil` | `O(n/t)`
| `TransformRange` | Process elements in a range | `start: number, endValue: number, step: number, processFunc: (index: number, value: any) -> any` | `nil` | `O(n)`

###### n is the amount of elements, and t is the number of threads.

### Usage Example
```lua
local InfArr = require(game.ReplicatedStorage.InfArray)

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

-- Process all elements in parallel with 4 threads
t:ParallelTransform(function(index, value)
    return value * 2
end, 4)

print(t:Find(8))
print(t:GetTotalLen())
print(t:GetValueAtIndex(5))
t:Replace(5, 'replace thing')
print(t:GetValueAtIndex(5))
```

### Limitations

* Compatible with only listed tables.
* Less performant than the actual implementation of tables.
* Initializations beyond 2^24 elements may be significantly slower.
