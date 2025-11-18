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
-- if it's a runtime error then ctor will work fine, but running will cause an error, which will get saved in thread.lua.global.results
do
	local thread = Thread([[
error'here'
]])

	-- still need to join error'd thread
	thread:join()
	local exitStatus = thread.lua.global.exitStatus
	assert.eq(exitStatus, false)

	local errmsg = thread.lua.global.errmsg
	assert(errmsg:find'here')

	local results = thread.lua.global.results
	assert.eq(results, nil)
end

-- make sure thread pools init code syntax errors fail correctly
do
	-- init errors will error before ready() needs to be called
	-- if there's a syntax error in the pool init code then it'll throw the error from the ctor
	local results = table.pack(xpcall(function()
		local pool = Pool{
			initcode = '(;;;;)',
		}
	end, function(err)
		return err..'\n'..debug.traceback()
	end))

	assert.eq(results[1], false)
	assert(results[2]:find"unexpected symbol near ';'")
end

-- make sure thread pools init code runtime errors fail correctly
do
	-- init errors will error before ready() needs to be called
	local pool = Pool{
		initcode = 'error"pools closed"',
	}

	-- thread runtime errors still need you to join the thread before they are gathered
	pool:closed()

	for _,worker in ipairs(pool) do
		local exitStatus = worker.thread.lua.global.exitStatus
		assert.eq(exitStatus, false)

		local errmsg = worker.thread.lua.global.errmsg
		assert(errmsg:find'pools closed')

		local results = worker.thread.lua.global.results
		assert.eq(results, nil)
	end
end

-- pool runtime errors
do
	-- init errors will error before ready() needs to be called
	local pool = Pool'error"pools closed"'

	-- still have to :cycle() once to hit the runtime error in `code`
	pool:cycle()

	-- thread runtime errors still need you to join the thread before they are gathered
	pool:closed()

	for _,worker in ipairs(pool) do
		local exitStatus = worker.thread.lua.global.exitStatus
		assert.eq(exitStatus, false)

		local errmsg = worker.thread.lua.global.errmsg
		assert(errmsg:find'pools closed')

		local results = worker.thread.lua.global.results
		assert.eq(results, nil)
	end
end

print'done'
