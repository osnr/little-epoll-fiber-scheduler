local ffi = require 'ffi'
ffi.cdef[[
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
   _fibers={},
   _fibers_to_resume={}
}
fiber.dispatch = function(f)
   local co = coroutine.create(f)
   fiber._fibers[coroutine.id(co)] = co
   table.insert(fiber._fibers_to_resume, co)
end
fiber.await = function(fd)
   local co = coroutine.running()

   -- rearm
   local ev = ffi.new('struct epoll_event')
   ev.data.u32 = coroutine.id(co)
   ffi.C.epoll_ctl(fiber._epfd, ffi.C.EPOLL_CTL_ADD, fd, ev)

   -- TODO: yield
   coroutine.yield()
end
fiber.sleep = function(us)
   -- FIXME: it's just await on a timerfd
   local fd
   fiber.await(fd)
end

fiber.runloop = function()
   fiber._epfd = ffi.C.epoll_create1(0)
   cassert(fiber._epfd ~= -1)
   while true do
      for _, co in ipairs(fiber._fibers_to_resume) do
         coroutine.resume(co)
      end
      fiber._fibers_to_resume = {}

      local numevents = ffi.C.epoll_wait(fiber._epfd, events, 1024, 500)
      for i = 0, numevents - 1 do
         local ev = events[i]
         table.insert(fiber._fibers_to_resume, fiber._fibers[ev.data.u32])
      end
      
   end
end

-- Usage:

fiber.dispatch(function()
      print('hi')
      
      local timerfd = ffi.C.timerfd_create(ffi.C.CLOCK_MONOTONIC, 0)
      local function sleep(ns)
         local spec = ffi.new('struct itimerspec', {it_value={tv_nsec=ns}})
         ffi.C.timerfd_settime(timerfd, 0, spec, nil)
         local buf = ffi.new('uint64_t[1]')
         cassert(ffi.C.read(timerfd, buf, ffi.sizeof(buf)) > 0)
      end

      print('hello')

      sleep(500000000)

      print('bye!')
end)

fiber.runloop()

