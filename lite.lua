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
	code = Lua code to load and run on the new thread
	func = Lua function to call upon init
--]]
function LiteThread:init(args)
	local code	-- init with code
	local func	-- init with function
	if type(args) == 'string' then
		code = args
	elseif type(args) == 'function' then
		func = args
	elseif type(args) == 'table' then
		code = args.code
		func = args.func
	end

	-- each thread needs its own lua_State
	self.lua = self.Lua()

	-- load our thread code within the new Lua state
	-- this will put a function on top of self.lua's stack
	--self.lua:load(code)
	-- or lazy way for now, just gen the code inside here:
	-- TODO instead of the extra lua closure, how about using self.lua:load() to load the code as a function, then use the lua lib for calling ffi.cast?
	-- then call it with xpcall?
	-- but no, the xpcall needs to be called from the new thread,
	-- so maybe it is safest to do here?
	local funcptr = self.lua([[
require 'ext.xpcall'(_G)	-- make sure xpcall arg fwding exists
local func = ...			-- ... is func

local reg = debug.getregistry()

-- xpcall safety wrapper of the function, so we can capture Lua errors and record them in the Lua state
-- (otherwise how does lua() handle errors?  does it immediately raise them in the parent?)
local function safefunc(...)
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

			do	-- separate code with a do / end block to prevent any call syntax from messing with the next statement
]]..(code or '')..[[
			end
			if func then
				func(...)
			end
		end,
		nil,	-- default handler appends traceback
		...		-- fwd args
	))

	return nil	-- so it can be cast to void* safely, for the thread's cfunc closure's sake
end

reg.safefunc = safefunc	-- must attach so it doesnt gc

-- just in case luajit gc's this, assign it to registry
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
local ffi = require 'ffi'

reg.funcptr = ffi.cast(']]..self.threadFuncTypeName..[[', safefunc)

return reg.funcptr	-- return the closure
]], func)

	self.funcptr = ffi.cast(self.threadFuncTypeName, funcptr)
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
