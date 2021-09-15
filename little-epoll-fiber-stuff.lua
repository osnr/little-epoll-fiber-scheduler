local ffi = require 'ffi'
ffi.cdef[[
char *strerror(int errnum);

int epoll_create1(int flags);
typedef union epoll_data {
    void    *ptr;
    int      fd;
    uint32_t u32;
    uint64_t u64;
} epoll_data_t;
struct epoll_event {
    uint32_t     events;    /* Epoll events */
    epoll_data_t data;      /* User data variable */
};
static const int EPOLL_CTL_ADD = 1;	/* Add a file descriptor to the interface.  */
static const int EPOLL_CTL_DEL = 2;	/* Remove a file descriptor from the interface.  */
static const int EPOLL_CTL_MOD = 3;	/* Change file descriptor epoll_event structure.  */
static const int EPOLLIN = 0x001;
static const int EPOLLONESHOT = 1u << 30;
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events,
               int maxevents, int timeout);

typedef long int time_t;
struct timespec {
    time_t tv_sec;                /* Seconds */
    long   tv_nsec;               /* Nanoseconds */
};
struct itimerspec {
    struct timespec it_interval;  /* Interval for periodic timer */
    struct timespec it_value;     /* Initial expiration */
};
static const int CLOCK_MONOTONIC = 1;
int timerfd_create(int clockid, int flags);
int timerfd_settime(int fd, int flags,
                    const struct itimerspec *new_value,
                    struct itimerspec *old_value);

ssize_t read(int fd, void *buf, size_t count);
]]

local function cassert(cond)
   if not cond then error(ffi.string(ffi.C.strerror(ffi.errno()))) end
end
coroutine.id = function(co) return tonumber(tostring(co):sub(8)) end

local fiber = {
   _fibers={}, -- Map<id, coroutine>
   _fibers_to_resume={}, -- Queue<coroutine>
   _num_fibers=0
}
fiber.dispatch = function(f)
   local co = coroutine.create(f)
   fiber._fibers[coroutine.id(co)] = co
   table.insert(fiber._fibers_to_resume, co)
   fiber._num_fibers = fiber._num_fibers + 1
end
fiber.await_add = function(fd)
   local co = coroutine.running()

   local ev = ffi.new('struct epoll_event')
   ev.data.u32 = coroutine.id(co)
   ev.events = bit.bor(ffi.C.EPOLLIN, ffi.C.EPOLLONESHOT)
   cassert(ffi.C.epoll_ctl(fiber._epfd, ffi.C.EPOLL_CTL_ADD, fd, ev) == 0)
end
fiber.await_rearm = function(fd)
   local co = coroutine.running()
   
   local ev = ffi.new('struct epoll_event')
   ev.data.u32 = coroutine.id(co)
   ev.events = bit.bor(ffi.C.EPOLLIN, ffi.C.EPOLLONESHOT)
   cassert(ffi.C.epoll_ctl(fiber._epfd, ffi.C.EPOLL_CTL_MOD, fd, ev) == 0)
end
fiber.await = function() coroutine.yield() end

fiber.runloop = function()
   fiber._epfd = ffi.C.epoll_create1(0)
   cassert(fiber._epfd ~= -1)
   local events = ffi.new('struct epoll_event[1024]')
   while true do
      for _, co in ipairs(fiber._fibers_to_resume) do
         local ok, err = coroutine.resume(co)
         if not ok then error(err) end

         if coroutine.status(co) == 'dead' then
            fiber._fibers[coroutine.id(co)] = nil
            fiber._num_fibers = fiber._num_fibers - 1
            if fiber._num_fibers <= 0 then os.exit() end
         end
      end
      fiber._fibers_to_resume = {}

      local numevents = ffi.C.epoll_wait(fiber._epfd, events, 1024, 200)
      for i = 0, numevents - 1 do
         local ev = events[i]
         table.insert(fiber._fibers_to_resume, fiber._fibers[ev.data.u32])
      end
   end
end

-- Usage:

local start = os.time()
local function printt(s)
   print(string.format("%.2f", os.time() - start), s)
end

-- These are 2 concurrent fibers that print and sleep and print.
-- They should be able to interleave properly.

fiber.dispatch(function()
      local timerfd = ffi.C.timerfd_create(ffi.C.CLOCK_MONOTONIC, 0)
      fiber.await_add(timerfd)
      local function sleep(s)
         local spec = ffi.new('struct itimerspec', {it_value={tv_sec=math.floor(s), tv_nsec=math.floor((s-math.floor(s))*1e9)}})
         cassert(ffi.C.timerfd_settime(timerfd, 0, spec, nil) == 0)
         fiber.await_rearm(timerfd)
         fiber.await()

         -- do i need to read this? (apparently not?)
         -- local buf = ffi.new('uint64_t[1]')
         -- cassert(ffi.C.read(timerfd, buf, ffi.sizeof(buf)) > 0)
      end

      printt('hello')

      sleep(1)

      printt("... it's been 1 second")
      
      sleep(5)

      printt("... it's been another 5 seconds")
end)

fiber.dispatch(function()
      local timerfd = ffi.C.timerfd_create(ffi.C.CLOCK_MONOTONIC, 0)
      fiber.await_add(timerfd)
      local function sleep(s)
         local spec = ffi.new('struct itimerspec', {it_value={tv_sec=math.floor(s), tv_nsec=math.floor((s-math.floor(s))*1e9)}})
         cassert(ffi.C.timerfd_settime(timerfd, 0, spec, nil) == 0)
         fiber.await_rearm(timerfd)
         fiber.await()
      end

      sleep(2)

      printt('\t[hi! 2s in]')

      sleep(3)

      printt("\t[hi again! 2s + 3s in]")
end)

fiber.runloop()

