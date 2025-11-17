#!/usr/bin/env luajit
-- verify errors within threads behave and don't segfault...
local table = require 'ext.table'
local assert = require 'ext.assert'
local Thread = require 'thread'

-- make sure thread syntax errors exit gracefully
-- this will throw an error inside Thread's ctor
local results = table.pack(xpcall(function()
	return Thread([[
(;;;;)
]])
end, function(err)
	return err..'\n'..debug.traceback()
end))
--assert.eq(results[1], false)
assert(results[2]:find[[unexpected symbol near ';']])


-- make sure thread runtime errors exit gracefully
-- if it's a runtime error then ctor will work fine, but running will cause an error, which will get saved in thread.lua:global'results'
local thread = Thread([[
error'here'
]])

-- still need to join error'd thread
thread:join()

local results = thread.lua:global'results'
--print(table.unpack(results, 1, results.n))
assert.eq(results[1], false)
assert(results[2]:find'here')
print'done'
