-- This is everything that goes into thread/thread.lua except the pthread stuff
-- It's useful for encasing Lua environments in other platforms' threads, i.e. in Java
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
local class = require 'ext.class'


local threadFuncTypeName = 'void*(*)(void*)'
local threadFuncType = ffi.typeof(threadFuncTypeName)


local LiteThread = class()

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
local runArg = ...

function _G.run(arg)
	local function collect(exitStatus, ...)
		_G.exitStatus = exitStatus
		if not exitStatus then
			_G.errmsg = ...
		else
			_G.results = table.pack(...)
		end
	end

	-- assign a global of the results when it's done
	collect(xpcall(function()
		-- separate code with a do / end block to prevent any call syntax from messing with the next statement
		do
]]..(code or '')..[[
		end
		if runArg then
			runArg(arg)
		end
	end, function(err)
		return err..'\n'..debug.traceback()
	end))

	return nil	-- so it can be cast to void* safely, for the thread's cfunc closure's sake
end

-- just in case luajit gc's this, assign it to _G
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
local ffi = require 'ffi'
_G.funcptr = ffi.cast(']]..threadFuncTypeName..[[', _G.run)
return _G.funcptr
]], func)

	self.funcptr = ffi.cast(threadFuncType, funcptr)
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

function LiteThread:getErr(msg)
	local WG = self.lua.global
	if WG.exitStatus then return true end
	return false, (msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(WG.errmsg)
end

function LiteThread:showErr(msg)
	local WG = self.lua.global
	if not WG.exitStatus then
		io.stderr:write((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(WG.errmsg)..'\n')
	end
end

function LiteThread:assertErr(msg)
	local WG = self.lua.global
	if not WG.exitStatus then
		error((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(WG.errmsg))
	end
end

return LiteThread
