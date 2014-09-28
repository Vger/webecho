local ltn12 = require "ltn12"
local remotedata = require "webmeet.incoming"

local emitted
local sink
local source

local faults = 0

local function myerror(...)
    faults = faults + 1
    print(...)
end

local results = {}
function emitted(reqid, data)
    if reqid == nil then
	if data then
	    myerror("Got error in ltn12 pump/source: \"" .. tostring(data) .. "\"")
	end
	return true
    end
    results[#results + 1] = { reqid, data }
    return true
end

sink = remotedata(emitted)
source = ltn12.source.string(string.char(0, 1) .. "a"
.. string.char(5, 3) .. "lol"
.. string.char(134, 3, 7) .. "nothing"
)
ltn12.pump.all(source, sink)

local expect_results = {
    { 0, "a" },
    { 5, "lol" },
    { 390, "nothing" },
}

local num_results = #results
if num_results ~= #expect_results then
    myerror("Num results: " .. tostring(num_results) .. " Expected: " .. tostring(#expect_results))
    if num_results < #expect_results then
	num_results = #expect_results
    end
end

for i = 1, num_results do
    local result = results[i]
    local expected_result = expect_results[i]
    local reqid, data
    local expect_reqid, expect_data
    if result then
	reqid, data = result[1], result[2]
    end
    if expected_result then
	expect_reqid, expect_data = expected_result[1], expected_result[2]
    end

    if reqid ~= expect_reqid then
	myerror("Item #" .. tostring(i) .. ": " .. "Request id: " .. tostring(reqid) .. " Expected: " .. tostring(expect_reqid))
    end
    if data ~= expect_data then
	myerror("Item #" .. tostirng(i) .. ": " .. "Data: " .. tostring(data) .. " Expected: " .. tostring(expect_data))

    end
end

if faults == 0 then
    print("SUCCESS")
end
