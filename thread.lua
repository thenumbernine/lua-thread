-- posix threads library
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
local pthread = require 'ffi.req' 'c.pthread'
local class = require 'ext.class'
local Lua = require 'lua'

local Thread = class()

--[[
code = Lua code to load and run on the new thread
arg = cdata to pass to the thread
--]]
function Thread:init(code, arg)
	-- each thread needs its own lua_State
	self.lua = Lua()

	-- load our thread code within the new Lua state
	-- this will put a function on top of self.lua's stack
	--self.lua:load(code)

	-- or lazy way for now, just gen the code inside here:
	-- TODO lua() call will cast the function closure to a uintptr_t ...
	-- TODO instead do void* ?
	local funcptr = self.lua([[
local run = function(arg)
]]..code..[[
end

local ffi = require 'ffi'
local runClosure = ffi.cast('void *(*)(void *)', run)
-- just in case luajit gc's this
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
_G.run = run
_G.runClosure = runClosure
return runClosure
]])
	self.lua(code)

	self.funcptr = ffi.cast('void*(*)(void*)', funcptr)
	self.id = ffi.new'pthread_t[1]'
	assert(type(arg) == 'nil' or type(arg) == 'cdata')
	arg = ffi.cast('void*', arg)
	pthread_assert(pthread.pthread_create(self.id, nil, funcptr, arg))
end

function Thread:__gc()
	self:close()
end

function Thread:close()
	if self.lua then
		self.lua:close()
		self.lua = nil
	end
end

-- static function
if ffi.os == 'Windows' then
	
	-- TODO proper header generation in include/
	local kernel32 = ffi.load'kernel32'

	ffi.cdef[[

typedef struct _SYSTEM_INFO {
	union {
		uint32_t dwOemId;
		struct {
			uint16_t wProcessorArchitecture;
			uint16_t wReserved;
		};
	};
	uint32_t dwPageSize;
	void* lpMinimumApplicationAddress;
	void* lpMaximumApplicationAddress;
	size_t dwActiveProcessorMask;
	uint32_t dwNumberOfProcessors;
	uint32_t dwProcessorType;
	uint32_t dwAllocationGranularity;
	uint16_t wProcessorLevel;
	uint16_t wProcessorRevision;
} SYSTEM_INFO;

void GetSystemInfo(SYSTEM_INFO* lpSystemInfo);
]]

	function Thread.numThreads()
		local sysinfo = ffi.new'SYSTEM_INFO'
		kernel32.GetSystemInfo(sysinfo)
		return tonumber(sysinfo.dwNumberOfProcessors)
	end
else
	require 'ffi.req' 'c.unistd'	-- sysconf

	function Thread.numThreads()
		return tonumber(ffi.C.sysconf(ffi._SC_NPROCESSORS_ONLN))
	end
end

return Thread
