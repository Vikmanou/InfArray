local InfArray = require('../InfArray')


local function primeCount(n: number, prime: number): number
	local exp = 0
	while n % prime == 0 do
		exp += 1
		n //= prime
	end
	return exp
end


return function(n: number): InfArray.InfArray
	local sieve = InfArray.new(n, 0)

	for p = 2, n do
		if sieve:Get(p) ~= 0 then continue end

		sieve:Transform(p, n, p, function(mult, currentValue)
			return currentValue + primeCount(mult, p)
		end)
	end

	return sieve
end