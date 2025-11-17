#!/usr/bin/env luajit
-- verify errors within threads behave and don't segfault...
local table = require 'ext.table'
local assert = require 'ext.assert'
local Thread = require 'thread'
local Pool = require 'thread.pool'

-- make sure thread syntax errors exit gracefully
-- this will throw an error inside Thread's ctor
do
	local results = table.pack(xpcall(function()
		return Thread([[
(;;;;)
]])
	end, function(err)
		return err..'\n'..debug.traceback()
	end))

	--print(table.unpack(results, 1, results.n))
	assert.eq(results[1], false)
	assert(results[2]:find[[unexpected symbol near ';']])
end

-- make sure thread runtime errors exit gracefully
-- if it's a runtime error then ctor will work fine, but running will cause an error, which will get saved in thread.lua:global'results'
do
	local thread = Thread([[
error'here'
]])

	-- still need to join error'd thread
	thread:join()
	local results = thread.lua:global'results'

	--print(table.unpack(results, 1, results.n))
	assert.eq(results[1], false)
	assert(results[2]:find'here')
end

--[[ make sure thread pools init code syntax errors fail correctly
do
	-- init errors will error before ready() needs to be called
	-- if there's a syntax error in the pool init code then it'll throw the error from the ctor
	local pool = Pool{
		initcode = '(;;;;)',
	}
end
--]]

-- make sure thread pools init code runtime errors fail correctly
do
	-- init errors will error before ready() needs to be called
	local pool = Pool{
		initcode = 'error"pools closed"',
	}

	-- thread runtime errors still need you to join the thread before they are gathered
	pool:closed()

	for _,worker in ipairs(pool) do
		local results = worker.thread.lua:global'results'
		assert.eq(results[1], false)
		assert(results[2]:find'pools closed')
	end
end

-- pool runtime errors
do
	-- init errors will error before ready() needs to be called
	local pool = Pool'error"pools closed"'

	-- if we stop here and check errors we'll find no errors, since the .code hasn't even run yet ... so ...
	-- if we pool:cycle() then it'll pool:ready() and the thread will error ...
	-- and then pool:wait() ... but nothing will signal that it's done ...
	--[[...therefore NOTICE :cycle() + .code runtime errors IS NOT YET SAFE. it'll lock.
	pool:cycle()
	--]]
	--[[ also NOTICE :ready() itself and then :close() will kill the threads before they can even run .code and throw an error
	pool:ready()
	--]]
	-- [[ the only way to even hit this error (and then fail without deadlocking) is...
	pool:ready()
	-- wait for all threads to reach their error
	-- otherwise if one hasn't reached it yet and we :closed() then it'll signal done, and that thread will return before thrown error, and its results will be "ok"
	-- this sort of works ... but it is time-sensitive ...
	require 'ffi'.C.usleep(100000)
	-- this stalls and crashes:
	--for _,worker in ipairs(pool) do worker.thread:join() end
	-- so TODO TODO TODO make ready/wait/worker code to handle errors within .code ... hmm ...
	--]]

	-- thread runtime errors still need you to join the thread before they are gathered
	pool:closed()

	for _,worker in ipairs(pool) do
		local results = worker.thread.lua:global'results'
		--print(table.unpack(results, 1, results.n))
		assert.eq(results[1], false)
		assert(results[2]:find'pools closed')
	end
end

print'done'
