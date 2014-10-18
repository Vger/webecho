local ltn12 = require "ltn12"
local incoming = require "webmeet.incoming"

local faults = 0

local function myerror(...)
    faults = faults + 1
    print(...)
end

local function mainwork()
    local sink, err = incoming(function() end)
    if not sink then
	myerror(err or "Sink could not be created")
	return
    end
    local source = ltn12.source.string(string.char(1) .. "a"
    .. string.char(3) .. "lol"
    .. string.char(130,3) .. string.rep("nothing", 55) .. "B"
    )
    ltn12.pump.all(source, sink)

    local results = {}
    while true do
	local data = sink:recv()
	if not data then
	    break
	end
	results[#results + 1] = data
    end
    return results
end

local results = mainwork()

local expect_results = {
    "a",
    "lol",
    string.rep("nothing", 55) .. "B",
}

local num_results = #results
if num_results ~= #expect_results then
    myerror("Num results: " .. tostring(num_results) .. " Expected: " .. tostring(#expect_results))
    if num_results < #expect_results then
	num_results = #expect_results
    end
end

for i = 1, num_results do
    local data = results[i]
    local expect_data = expect_results[i]
    if data ~= expect_data then
	myerror("Item #" .. tostring(i) .. ": " .. "Data: " .. tostring(data) .. " Expected: " .. tostring(expect_data))
    end
end

if faults == 0 then
    print("SUCCESS")
end
