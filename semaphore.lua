require 'ext.gc'
local ffi = require 'ffi'
local class = require 'ext.class'
local sem = require 'ffi.req' 'c.semaphore'	-- sem_t
local thread_assert = require 'thread.assert'


local int_1 = ffi.typeof'int[1]'
local sem_t_1 = ffi.typeof'sem_t[1]'
local sem_t_ptr = ffi.typeof'sem_t*'


local Semaphore = class()

function Semaphore:init(n, shared)
	n = n or 0
	self.id = sem_t_1()
	thread_assert(sem.sem_init(self.id, shared and 1 or 0, n), 'sem_init')
end

function Semaphore:destroy()
	if not self.id then return true end
	local err = sem.sem_destroy(self.id)
	if err == 0 then self.id = nil end
	return 0 == err
end

function Semaphore:__gc()
	self:destroy()
end

-- wrap a previously created sem_t* and overwrite the destroy function
-- static method
function Semaphore:wrap(id)
	return setmetatable({
		id = ffi.cast(sem_t_ptr, id),
		destroy = function() end,
	}, Semaphore)
end

function Semaphore:close()
	local err = sem.sem_close(self.id)
	return 0 == err, err
end

-- TODO sem_unlink but names ...

function Semaphore:wait()
	local err = sem.sem_wait(self.id)
	return 0 == err, err
end

-- dt is a `struct timespec *` ffi.new
function Semaphore:timedwait(dt)
	assert(dt, "expected dt")
	local err = sem.sem_timedwait(self.id, dt)
	return 0 == err, err
end

function Semaphore:trywait()
	local err = sem.sem_trywait(self.id)
	return 0 == err, err
end

function Semaphore:post()
	local err = sem.sem_post(self.id)
	return 0 == err, err
end

-- should this return true/value and value
-- or should this return value and error on fail?
-- I'll do like pcall, true/false then value
function Semaphore:getvalue()
	local value = int_1()
	local err = sem.sem_getvalue(self.id, value)
	if 0 == err then
		return true, value[0]
	else
		return false, err
	end
end

return Semaphore
