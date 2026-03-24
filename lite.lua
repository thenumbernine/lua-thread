-- This is everything that goes into thread/thread.lua except the pthread stuff
-- It's useful for encasing Lua environments in other platforms' threads, i.e. in Java
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
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
	func = Lua function to call upon init

	threadFuncTypeName = override the thread function C type, default is pthread type
--]]
function LiteThread:init(args)
	-- each thread needs its own lua_State
	self.lua = self.Lua()


	local code	-- init with code
	local func	-- init with function
	if type(args) == 'string' then
		code = args
	elseif type(args) == 'function' then
		func = args
	elseif type(args) == 'table' then
		code = args.code
		func = args.func

		-- allow override
		self.threadFuncTypeName = args.threadFuncTypeName

		if args.init then
			args.init(self)
		end
	end


	-- hmm, new concept, using the same Lua state for multiple Lua-functions
	-- in this case I would want to initialize lite threads with no functions up front, and add to it later
	if func ~= nil
	or code ~= nil
	then
		-- load our thread code within the new Lua state
		-- this will put a function on top of self.lua's stack
		--self.lua:load(code)
		-- or lazy way for now, just gen the code inside here:
		-- TODO instead of the extra lua closure, how about using self.lua:load() to load the code as a function, then use the lua lib for calling ffi.cast?
		-- then call it with xpcall?
		-- but no, the xpcall needs to be called from the new thread,
		-- so maybe it is safest to do here?
		self.funcptr = self:createFuncPtr(self.threadFuncTypeName, func, code)
	end
end

--[[
for a Lua function 'func' or Lua code 'code',
create a new closure, cast it to funcptr, and return it

TODO I gave 'func' as lua-function a chance
but its such a mess with upvalues
that I do regret it, and should and will take it out soon.

Same with 'arg', get rid of that too.

So 'initCode' runs with ... from this function's extra args (upon init)
and 'code' runs with ... from teh function call.
--]]
function LiteThread:createFuncPtr(threadFuncTypeName, func, code, initCode, ...)
	local funcptr = self.lua([[
require 'ext.xpcall'(_G)	-- make sure xpcall arg fwding exists
local func = ...			-- ... is func

]]..(initCode or '')..[[

local reg = debug.getregistry()

-- xpcall safety wrapper of the function, so we can capture Lua errors and record them in the Lua state
-- (otherwise how does lua() handle errors?  does it immediately raise them in the parent?)
local function safefunc(...)
	-- This function will be run on a dif thread,
	-- albeit from within the same Lua state

	-- TODO for multiple functions in a luaState,
	-- we will have to store multiple results,
	-- but only a single exit-status
	-- TODO hmm, maybe I should decouple results from exitStatus?
	-- or TODO how about get rid of safefunc() and just make sure to run funcptr with a xpcall that captures the call stack?
	local function collect(exitStatus, ...)
		reg.exitStatus = exitStatus
		if not exitStatus then
			reg.errmsg = ...
		else
			reg.results = table.pack(...)
		end
	end

	-- assign a global of the results when it's done
	collect(xpcall(
		function(...)

			-- arg is backwards compat. I gotta clean this all up eventually
			local arg = ...

]]..(code or '')..[[

]]..(func and [[
			do	-- separate code with a do / end block to prevent any call syntax from messing with the next statement
				func(...)
			end
]] or '')..[[
		end,
		nil,	-- default handler appends traceback
		...		-- fwd args
	))

	return nil	-- so it can be cast to void* safely, for the thread's cfunc closure's sake
end

-- must attach so it doesnt gc
reg.thread_funcs = reg.thread_funcs or {}
table.insert(reg.thread_funcs, safefunc)

-- just in case luajit gc's this, assign it to registry
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
local ffi = require 'ffi'

reg.thread_closures = reg.thread_closures or {}
local funcptr = ffi.cast(']]..threadFuncTypeName..[[', safefunc)
table.insert(reg.thread_closures, funcptr)

return funcptr	-- return the closure
]], func, ...)

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


-- TODO all this exitStatus stuf is currently setup for a single callback
-- but I just decoupled single-function from lite-thread
-- so best TODO is only invoke funcptr's returned with an xpcall from the thread.lua state
-- (and not from within its own Lua code)
-- (because successive of those will overwrite a fail exit status)
-- and another TODO is to move the .results stuff into thread.thread

function LiteThread:getExitStatus()
	return self.lua[[ return debug.getregistry().exitStatus ]]
end

function LiteThread:getErrMsg()
	return self.lua[[ return debug.getregistry().errmsg ]]
end

-- redundant ... why do I have this?
function LiteThread:getErr(msg)
	if self:getExitStatus() then return true end
	local errmsg = self:getErrMsg()
	return false, (msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg)
end

function LiteThread:showErr(msg)
	if self:getExitStatus() then return true end
	local errmsg = self:getErrMsg()
	io.stderr:write((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg)..'\n')
end

function LiteThread:assertErr(msg)
	if self:getExitStatus() then return true end
	local errmsg = self.lua[[ return debug.getregistry().errmsg ]]
	error((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(errmsg))
end

return LiteThread
