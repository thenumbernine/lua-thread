require 'ext.gc'
local ffi = require 'ffi'
local class = require 'ext.class'
local sem = require 'ffi.req' 'c.semaphore'	-- sem_t
local thread_assert = require 'thread.assert'


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

function Semaphore:wait()
	local err = sem.sem_wait(self.id)
	return 0 == err, err
end

function Semaphore:post()
	local err = sem.sem_post(self.id)
	return 0 == err, err
end

return Semaphore
