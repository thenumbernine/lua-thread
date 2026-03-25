--[[
This is everything that goes into thread/thread.lua except the pthread stuff
It's useful for encasing Lua environments in other platforms' threads, i.e. in Java


TODO
- get rid of 'func' ... or move it into thread.thread.  only use inline code.
- get rid of xpcall and exitStatus and results ... move those into thread.thread as well.
- get rid of ctor args as well.

This will just be:
1) wrapper of a lua state
2) helper-function for creating, saving, and returning closures within the state

--]]
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'


local LiteThread = class()

-- Has to be a string for code-injection's sake, for carrying across threads' Lua states.
-- (because I don't have any certain way to pass ctypes across Lua states.)
LiteThread.threadFuncTypeName = 'void*(*)(void*)'

if langfix then
	LiteThread.Lua = require 'lua.langfix'
else
	LiteThread.Lua = require 'lua'
end

--[[
args = code of the thread, to be inserted and run on the new Lua state.
	-or-
args = function of the thread, to be converted and run on the new Lua state.
	-or-
args:
	init = initialization callback to run on self,
		useful for initializing the Lua state and before the Lua state is used to create the callback,
		(i.e. if there's any typedefs that need to go in it for the ffi.cast of the function-pointer to work)
	code = Lua code to load and run on the new thread

	threadFuncTypeName = override the thread function C type, default is pthread type
--]]
function LiteThread:init(args)
	-- each thread needs its own lua_State
	self.lua = self.Lua()


	local code	-- init with code
	if args ~= nil then
		if type(args) == 'string' then
			code = args
		end
		assert.type(args, 'table')

		code = args.code

		-- allow override
		self.threadFuncTypeName = args.threadFuncTypeName

		if args.init then
			args.init(self)
		end
	end

	-- hmm, new concept, using the same Lua state for multiple Lua-functions
	-- in this case I would want to initialize lite threads with no functions up front, and add to it later
	if code ~= nil then
		-- load our thread code within the new Lua state
		-- this will put a function on top of self.lua's stack
		--self.lua:load(code)
		-- or lazy way for now, just gen the code inside here:
		-- TODO instead of the extra lua closure, how about using self.lua:load() to load the code as a function, then use the lua lib for calling ffi.cast?
		-- then call it with xpcall?
		-- but no, the xpcall needs to be called from the new thread,
		-- so maybe it is safest to do here?
		self.funcptr = self:createFuncPtr(self.threadFuncTypeName, '', code)
	end
end

--[[
for Lua code 'code',
create a new closure, cast it to funcptr, and return it

So 'initCode' runs with ... from this function's extra args (upon init)
and 'code' runs with ... from teh function call.
--]]
function LiteThread:createFuncPtr(
	threadFuncTypeName,	-- optional, nil defaults to self.threadFuncTypeName
	initCode,			-- optional, nil
	code,				-- required
	...
)
	--
	assert(code, "createFuncPtr expects code")

	local funcptr = self.lua(
(initCode or '')..[[

local safefunc
local funcinfo
function safefunc(...)
	-- This function will be run on a dif thread,
	-- albeit from within the same Lua state

	-- use `funcinfo` which is an element of the reg.thread_funcs
	-- TODO alternatively ...
	-- could I use thread.lua to invoke this with pcall and then read the error state off its stack?
	-- but that wouldn't help me in using this with multithreaded C APIs ...
	return (function(exitStatus, ...)
		funcinfo.exitStatus = exitStatus
		if not exitStatus then
			funcinfo.errmsg = ...
		else
			return ...
		end

	-- xpcall safety wrapper of the function, so we can capture Lua errors and record them in the Lua state
	-- (otherwise how does lua() handle errors?  does it immediately raise them in the parent?)
	end)(xpcall(
		function(...)

]]..code..[[

		end,
		function(err)
			return err..'\n'..debug.traceback()	-- I could use ext.xpcall but meh
		end,	-- handler appends traceback
		...		-- fwd args
	))
end

-- just in case luajit gc's this, assign it to registry
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
local ffi = require 'ffi'
local funcptr = ffi.cast(']]..threadFuncTypeName..[[', safefunc)

-- key = string of hex of ptr of safefunc
local funckey = bit.tohex(ffi.cast('uintptr_t', funcptr), bit.lshift(ffi.sizeof'uintptr_t', 1))

-- save the closure and callback in reg so it doesnt gc
-- use key as funcptr so you can later store other stuff like exitStatus
local reg = debug.getregistry()
reg.thread_funcs = reg.thread_funcs or {}
funcinfo = {funcptr=funcptr, safefunc=safefunc}
reg.thread_funcs[funckey] = funcinfo

return funcptr	-- return the closure
]], ...)

	return ffi.cast(threadFuncTypeName, funcptr)
end

function LiteThread:__gc()
	self:close()
end

function LiteThread:close()
	if self.lua then
		self.lua:close()
		self.lua = nil
	end
end

-- since lite-thread is made for multiple functions
-- you will need to provide your own funckey to retrieve exit status
-- generate it with the same method of funckey assignment above.

function LiteThread:getExitStatus(funckey)
	assert.type(funckey, 'string')
	return self.lua([[
local funckey = ...
return debug.getregistry().thread_funcs[funckey].exitStatus
]], funckey)
end

function LiteThread:getErrMsg(funckey)
	assert.type(funckey, 'string')
	return self.lua([[
local funckey = ...
return debug.getregistry().thread_funcs[funckey].errmsg
]], funckey)
end

return LiteThread
