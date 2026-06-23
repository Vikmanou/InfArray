local InfArray = require('../InfArray')

return function(n: number): InfArray.InfArray
	local phi = InfArray.new(n)

	for i = 1, n do
		phi:Set(i, i)
	end

	phi:Transform(2, n, 1, function(i: number, v1: any)
		if v1 == i then
			phi:Transform(i + i, n, i, function(j: number, v2: any)
				return v2 - v2/i
			end)
			
			return v1 - v1/i
		end
		
		return v1
	end)
	
	return phi
end