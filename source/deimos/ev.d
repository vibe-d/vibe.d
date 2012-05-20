module deimos.ev;

/*
 * libev native API header
 *
 * Copyright (c) 2007,2008,2009,2010,2011 Marc Alexander Lehmann <libev@schmorp.de>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modifica-
 * tion, are permitted provided that the following conditions are met:
 *
 *   1.  Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *   2.  Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MER-
 * CHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPE-
 * CIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTH-
 * ERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Alternatively, the contents of this file may be used under the terms of
 * the GNU General Public License ("GPL") version 2 or any later version,
 * in which case the provisions of the GPL are applicable instead of
 * the above. If you wish to allow the use of your version of this file
 * only under the terms of the GPL and not to allow others to use your
 * version of this file under the BSD license, indicate your decision
 * by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL. If you do not delete the
 * provisions above, a recipient may use your version of this file under
 * either the BSD or the GPL.
 */

import core.stdc.signal;
import core.stdc.config; //c_long

extern(C):

/*****************************************************************************/

//TODO: Better way to define default versions
//TODO: EV_FEATURES_* is not working

/* pre-4.0 compatibility */
/*version = LIBEV4;
  version = LIBEV3_COMPAT;*/
version = EV_MULTIPLICITY;
version = EV_PERIODIC_ENABLE;
version = EV_STAT_ENABLE;
version = EV_IDLE_ENABLE;
version = EV_FORK_ENABLE;
version = EV_EMBED_ENABLE;
version = EV_ASYNC_ENABLE;
version = EV_SIGNAL_ENABLE;
version = EV_CHILD_ENABLE;
version = EV_PREPARE_ENABLE;
version = EV_CHECK_ENABLE;
version = ENABLE_ADDITIONAL_FEATURES;
//version = EV_WALK_ENABLE; not yet

version(LIBEV4)
{
    version = EV_CLEANUP_ENABLE;
}

/*****************************************************************************/

alias double ev_tstamp;
struct ev_loop_t;
enum EV_MINIMAL = 0;

/* these priorities are inclusive, higher priorities will be invoked earlier */
enum EV_MINPRI = -2;
enum EV_MAXPRI = 2;

alias /*volatile*/ shared sig_atomic_t EV_ATOMIC_T;

version(EV_STAT_ENABLE)
{
    version(Windows)
    {
        import core.stdc.time;
        static assert(false, "EV_STAT_ENABLE not supported on windows");
        //import core.sys.windows.sys.types;
        //import core.sys.windows.sys.stat;
    }
    else version(Posix)
    {
        import core.sys.posix.sys.stat;
    }
    else
    {
        static assert(false, "EV_STAT_ENABLE not supported on this platform");
    }
}
/* support multiple event loops? */
version(EV_MULTIPLICITY)
{
    /* TODO: These enum string are #defines in the C
     * header. They're used in function definitions:
     * void test(EV_P_ int hello)
     * D string mixins don't work in this case!
     */
    enum EV_P = "ev_loop_t* loop";                 /* a loop as sole parameter in a declaration */
    enum EV_P_ = "ev_loop_t* loop,";               /* a loop as first of multiple parameters */
    enum EV_A = "loop";                            /* a loop as sole argument to a function call */
    enum EV_A_ = EV_A;                             /* a loop as first of multiple arguments */
    enum EV_DEFAULT_UC = "ev_default_loop_uc()";   /* the default loop, if initialised, as sole arg */
    enum EV_DEFAULT_UC_ = EV_DEFAULT_UC;           /* the default loop as first of multiple arguments */
    enum EV_DEFAULT = "ev_default_loop(0)";        /* the default loop as sole arg */
    enum EV_DEFAULT_ = EV_DEFAULT;                 /* the default loop as first of multiple arguments */             
}
else
{
    static assert(false, "BUG: EV_MULTIPLICITY is required");
}

/*****************************************************************************/

enum EV_VERSION_MAJOR = 4;
enum EV_VERSION_MINOR = 4;

/* eventmask, revents, events... */
enum : uint
{
    EV_UNDEF    = 0xFFFFFFFF, /** guaranteed to be invalid */
    EV_NONE     =       0x00, /** no events */
    EV_READ     =       0x01, /** ev_io detected read will not block */
    EV_WRITE    =       0x02, /** ev_io detected write will not block */
    EV__IOFDSET =       0x80, /** internal use only */
    EV_IO       =    EV_READ, /** alias for type-detection */
    EV_PERIODIC = 0x00000200, /** periodic timer timed out */
    EV_SIGNAL   = 0x00000400, /** signal was received */
    EV_CHILD    = 0x00000800, /** child/pid had status change */
    EV_STAT     = 0x00001000, /** stat data changed */
    EV_IDLE     = 0x00002000, /** event loop is idling */
    EV_PREPARE  = 0x00004000, /** event loop about to poll */
    EV_CHECK    = 0x00008000, /** event loop finished poll */
    EV_EMBED    = 0x00010000, /** embedded event loop needs sweep */
    EV_FORK     = 0x00020000, /** event loop resumed in child */
    EV_ASYNC    = 0x00040000, /** async intra-loop signal */
    EV_CUSTOM   = 0x01000000, /** for use by user code */
    EV_ERROR    = 0x80000000, /** sent when an error occurs */
}

version(LIBEV4)
{
    enum : uint
    {
        EV_TIMER    = 0x00000100, /** timer timed out */
        EV_CLEANUP  = 0x00040000, /** event loop resumed in child */
    }
    version(LIBEV3_COMPAT)
    {
        enum : uint
        {
            EV_TIMEOUT = EV_TIMER,   /** pre 4.0 API compatibility */
        }
    }
}

/* can be used to add custom fields to all watchers, while losing binary compatibility */
template EV_COMMON()
{
    void* data; ///
}

template EV_CB_DECLARE(TYPE)
{
    void function (ev_loop_t*, TYPE*, int) cb; ///
}
/+
#ifndef EV_CB_INVOKE
# define EV_CB_INVOKE(watcher,revents) (watcher)->cb (EV_A_ (watcher), (revents))
#endif+/

/* not official, do not use */
//#define EV_CB(type,name) void name (EV_P_ struct ev_ ## type *w, int revents)

/*
 * struct member types:
 * private: you may look at them, but not change them,
 *          and they might not mean anything to you.
 * ro: can be read anytime, but only changed when the watcher isn't active.
 * rw: can be read and modified anytime, even when the watcher is active.
 *
 * some internal details that might be helpful for debugging:
 *
 * active is either 0, which means the watcher is not active,
 *           or the array index of the watcher (periodics, timers)
 *           or the array index + 1 (most other watchers)
 *           or simply 1 for watchers that aren't in some array.
 * pending is either 0, in which case the watcher isn't,
 *           or the array index + 1 in the pendings array.
 */

static if(EV_MINPRI == EV_MAXPRI)
{
    template EV_DECL_PRIORITY()
    {
    }
}
else
{
    template EV_DECL_PRIORITY()
    {
        int priority; ///
    }
}

/* shared by all watchers */
template EV_WATCHER(TYPE)
{
    int active;                 // private
    int pending;                // private
    mixin EV_DECL_PRIORITY;     // private
    mixin EV_COMMON;            // rw
    mixin EV_CB_DECLARE!(TYPE); // private
}

template EV_WATCHER_LIST(TYPE)
{
    mixin EV_WATCHER!(TYPE);
    ev_watcher_list* next;      // private
}

template EV_WATCHER_TIME(TYPE)
{
    mixin EV_WATCHER!(TYPE);
    ev_tstamp at;               // private
}

/* base class, nothing to see here unless you subclass */
struct ev_watcher
{
  mixin EV_WATCHER!(ev_watcher);
}

/* base class, nothing to see here unless you subclass */
struct ev_watcher_list
{
  mixin EV_WATCHER_LIST!(ev_watcher_list);
}

/* base class, nothing to see here unless you subclass */
struct ev_watcher_time
{
  mixin EV_WATCHER_TIME!(ev_watcher_time);
}

/* invoked when fd is either EV_READable or EV_WRITEable */
/* revent EV_READ, EV_WRITE */
struct ev_io
{
  mixin EV_WATCHER_LIST!(ev_io);

  int fd;     /* ro */
  int events; /* ro */
}

/* invoked after a specific time, repeatable (based on monotonic clock) */
/* revent EV_TIMEOUT */
struct ev_timer
{
  mixin EV_WATCHER_TIME!(ev_timer);

  ev_tstamp repeat; /* rw */
}

version(EV_PERIODIC_ENABLE)
{
    /* invoked at some specific time, possibly repeating at regular intervals (based on UTC)
     revent EV_PERIODIC */
    struct ev_periodic
    {
      mixin EV_WATCHER_TIME!(ev_periodic);
    
      ev_tstamp offset; /* rw */
      ev_tstamp interval; /* rw */
      ev_tstamp function(ev_periodic *w, ev_tstamp now) reschedule_cb; /* rw */
    }
}

/* invoked when the given signal has been received */
/* revent EV_SIGNAL */
struct ev_signal
{
  mixin EV_WATCHER_LIST!(ev_signal);

  int signum; /* ro */
}

/* invoked when sigchld is received and waitpid indicates the given pid */
/* revent EV_CHILD */
/* does not support priorities */
struct ev_child
{
  mixin EV_WATCHER_LIST!(ev_child);

  int flags;   /* private */
  int pid;     /* ro */
  int rpid;    /* rw, holds the received pid */
  int rstatus; /* rw, holds the exit status, use the macros from sys/wait.h */
}

version(EV_STAT_ENABLE)
{
    version(Windows)
    {
        static assert(false, "EV_STAT_ENABLE not supported on windows");
        // Maybe this should work? _stati64?
        //static import stat = std.c.windows.stat;
        //alias stat.stat_t ev_statdata;
    }
    else version(Posix)
    {
        static import stat = core.sys.posix.sys.stat;
        alias stat.stat_t ev_statdata;
    }
    else
    {
        static assert(false, "EV_STAT_ENABLE not supported on this platform");
    }
    
    /* invoked each time the stat data changes for a given path
     revent EV_STAT */
    struct ev_stat
    {
      mixin EV_WATCHER_LIST!(ev_stat);
    
      ev_timer timer;     /* private */
      ev_tstamp interval; /* ro */
      const (char)* path;   /* ro */
      ev_statdata prev;   /* ro */
      ev_statdata attr;   /* ro */
    
      int wd; /* wd for inotify, fd for kqueue */
    }
}

version(EV_IDLE_ENABLE)
{
    /* invoked when the nothing else needs to be done, keeps the process from blocking
    revent EV_IDLE */
    struct ev_idle
    {
      mixin EV_WATCHER!(ev_idle);
    }
}

/* invoked for each run of the mainloop, just before the blocking call */
/* you can still change events in any way you like */
/* revent EV_PREPARE */
struct ev_prepare
{
  mixin EV_WATCHER!(ev_prepare);
}

/* invoked for each run of the mainloop, just after the blocking call */
/* revent EV_CHECK */
struct ev_check
{
  mixin EV_WATCHER!(ev_check);
}

version(EV_FORK_ENABLE)
{
    /* the callback gets invoked before check in the child process when a fork was detected
     revent EV_FORK */
    struct ev_fork
    {
      mixin EV_WATCHER!(ev_fork);
    }
}

version(LIBEV4)
{
    version(EV_CLEANUP_ENABLE)
    {
        /* is invoked just before the loop gets destroyed
         revent EV_CLEANUP */
        struct ev_cleanup
        {
          mixin EV_WATCHER!(ev_cleanup);
        }
    }
}

version(EV_EMBED_ENABLE)
{
    /* used to embed an event loop inside another
     the callback gets invoked when the event loop has handled events, and can be 0 */
    struct ev_embed
    {
      mixin EV_WATCHER!(ev_embed);
    
      ev_loop_t *other; /* ro */
      ev_io io;              /* private */
      ev_prepare prepare;    /* private */
      ev_check check;        /* unused */
      ev_timer timer;        /* unused */
      ev_periodic periodic;  /* unused */
      ev_idle idle;          /* unused */
      ev_fork fork;          /* private */
      version(LIBEV4)
      {
          version(EV_CLEANUP_ENABLE)
          {
              ev_cleanup cleanup; /* unused */
          }
      }
    }
}

version(EV_ASYNC_ENABLE)
{
    /* invoked when somebody calls ev_async_send on the watcher
     revent EV_ASYNC */
    struct ev_async
    {
      mixin EV_WATCHER!(ev_async);
    
      EV_ATOMIC_T sent; /* private */
    }
    //
    bool ev_async_pending(ev_async* watch)
    {
        if(watch.sent)
            return true;
        else
            return false;
    }
}

/+ ***************Not supported in D***************** 
/* the presence of this union forces similar struct layout */
union ev_any_watcher
{
  struct ev_watcher w;
  struct ev_watcher_list wl;

  struct ev_io io;
  struct ev_timer timer;
  struct ev_periodic periodic;
  struct ev_signal signal;
  struct ev_child child;
#if EV_STAT_ENABLE
  struct ev_stat stat;
#endif
#if EV_IDLE_ENABLE
  struct ev_idle idle;
#endif
  struct ev_prepare prepare;
  struct ev_check check;
#if EV_FORK_ENABLE
  struct ev_fork fork;
#endif
+ LIBEV4 only
#if EV_CLEANUP_ENABLE
  struct ev_cleanup cleanup;
#endif
+ End LIBEV4 only
#if EV_EMBED_ENABLE
  struct ev_embed embed;
#endif
#if EV_ASYNC_ENABLE
  struct ev_async async;
#endif
};
+/

enum : uint
{
    /* flag bits for ev_default_loop and ev_loop_t_new
     the default */
    EVFLAG_AUTO       = 0x00000000U, /* not quite a mask */
    /* flag bits */
    EVFLAG_NOENV      = 0x01000000U, /* do NOT consult environment */
    EVFLAG_FORKCHECK  = 0x02000000U, /* check for a fork in each iteration */
    /* debugging/feature disable */
    EVFLAG_NOINOTIFY  = 0x00100000U, /* do not attempt to use inotify */
    EVFLAG_SIGNALFD   = 0x00200000U, /* attempt to use signalfd */
    /* method bits to be ored together */
    EVBACKEND_SELECT  = 0x00000001U, /* about anywhere */
    EVBACKEND_POLL    = 0x00000002U, /* !win */
    EVBACKEND_EPOLL   = 0x00000004U, /* linux */
    EVBACKEND_KQUEUE  = 0x00000008U, /* bsd */
    EVBACKEND_DEVPOLL = 0x00000010U, /* solaris 8 */ /** NYI */
    EVBACKEND_PORT    = 0x00000020U, /* solaris 10 */
    EVBACKEND_ALL     = 0x0000003FU  /* all known backends */
}

version(LIBEV4)
{
    enum : uint
    {
        EVFLAG_NOSIGMASK = 0x00400000U,  /* avoid modifying the signal mask */
        EVBACKEND_MASK    = 0x0000FFFFU  /* all future backends */
    }
    version(LIBEV3_COMPAT)
    {
        enum : uint
        {
            EVFLAG_NOSIGFD    = 0 /* compatibility to pre-3.9 */
        }
    }
}
else
{
    enum : uint
    {
        EVFLAG_NOSIGFD    = 0 /* compatibility to pre-3.9 */
    }
}

int ev_version_major ();
int ev_version_minor ();

uint ev_supported_backends();
uint ev_recommended_backends();
uint ev_embeddable_backends();

ev_tstamp ev_time();
void ev_sleep (ev_tstamp delay); /* sleep for a while */

/* Sets the allocation function to use, works like realloc.
 * It is used to allocate and free memory.
 * If it returns zero when memory needs to be allocated, the library might abort
 * or take some potentially destructive action.
 * The default is your system realloc function.
 */
void ev_set_allocator(void* function(void* ptr, c_long size));

/* set the callback function to call on a
 * retryable syscall error
 * (such as failed select, poll, epoll_wait)
 */
void ev_set_syserr_cb(void function(const (char*) msg));

version(EV_MULTIPLICITY)
{
    __gshared ev_loop_t* ev_default_loop_ptr;
    ev_loop_t* ev_default_loop_uc()
    {
      return ev_default_loop_ptr;
    }

    version(LIBEV4)
    {
        ev_loop_t *ev_default_loop(uint flags);
    }
    else
    {
        ev_loop_t* ev_default_loop_init(uint flags);
        /* the default loop is the only one that handles signals and child watchers 
         you can call this as often as you like */
        ev_loop_t *ev_default_loop(uint flags)
        {
          ev_loop_t* loop = ev_default_loop_uc();
        
          if (!loop)
            {
              loop = ev_default_loop_init(flags);
            }
        
          return loop;
        }
    }
    
    /* create and destroy alternative loops that don't handle signals */
    ev_loop_t* ev_loop_new (uint flags);
    version(LIBEV4){}
    else
    {
        void ev_loop_destroy (/*mixin(EV_P)*/ ev_loop_t* loop);
        void ev_loop_fork (/*mixin(EV_P)*/ ev_loop_t* loop);
    }
    
    ev_tstamp ev_now (/*mixin(EV_P)*/ ev_loop_t* loop); /* time w.r.t. timers and the eventloop, updated after each poll */
}
else
{
    //This part should work, but it's not tested:
    static assert(false, "BUG: EV_MULTIPLICITY is required");

    int ev_default_loop(uint flags); /* returns true when successful */
    __gshared ev_tstamp ev_rt_now;
    ev_tstamp ev_now() //
    {
      return ev_rt_now;
    }
}

int ev_is_default_loop(/*mixin(EV_P)*/ ev_loop_t* loop) ///
{
    version(EV_MULTIPLICITY)
    {
      return !!(mixin(EV_A) == ev_default_loop_ptr);
    }
    else
      return 1;
}

version(LIBEV4)
{
    /* destroy event loops, also works for the default loop */
    void ev_loop_destroy (/*mixin(EV_P)*/ ev_loop_t* loop);

    /* this needs to be called after fork, to duplicate the loop
     when you want to re-use it in the child
     you can call it in either the parent or the child
     you can actually call it at any time, anywhere :) */
    void ev_loop_fork (/*mixin(EV_P)*/ ev_loop_t* loop);
}
else
{
    void ev_default_destroy(); /* destroy the default loop */
    
    /* this needs to be called after fork, to duplicate the default loop
    * if you create alternative loops you have to call ev_loop_t_fork on them
    * you can call it in either the parent or the child
    * you can actually call it at any time, anywhere :) */
    void ev_default_fork ();
}

uint ev_backend(/*mixin(EV_P)*/ ev_loop_t* loop); /* backend in use by loop */

void ev_now_update(/*mixin(EV_P)*/ ev_loop_t* loop); /* update event loop time */

version(EV_WALK_ENABLE)
{
    /* walk (almost) all watchers in the loop of a given type, invoking the
    * callback on every such watcher. The callback might stop the watcher,
    * but do nothing else with the loop */
    void ev_walk (/*mixin(EV_P_)*/ ev_loop_t* loop, int types, void function(/*mixin(EV_P_)*/ ev_loop_t* loop, int type, void* w));
}

version(LIBEV4)
{
    /* ev_run flags values */
    enum {
      EVRUN_NOWAIT = 1, /** do not block/wait */
      EVRUN_ONCE   = 2  /** block *once* only */
    }
    
    /* ev_break how values */
    enum {
      EVBREAK_CANCEL = 0, /** undo unloop */
      EVBREAK_ONE    = 1, /** unloop once */
      EVBREAK_ALL    = 2  /** unloop all loops */
    }
}
else
{
    enum
    {
        EVLOOP_NONBLOCK =1, /* do not block/wait */
        EVLOOP_ONESHOT = 2 /* block *once* only */
    }
    enum
    {
        EVUNLOOP_CANCEL = 0, /* undo unloop */
        EVUNLOOP_ONE    = 1, /* unloop once */
        EVUNLOOP_ALL    = 2 /* unloop all loops */
    }
}

version(LIBEV4)
{
    void ev_run (/*mixin(EV_P_)*/ ev_loop_t* loop, int flags);
    void ev_break (/*mixin(EV_P_)*/ ev_loop_t* loop, int how); /* set to 1 to break out of event loop, set to 2 to break out of all event loops */
}
else
{
    void ev_loop (/*mixin(EV_P_)*/ ev_loop_t* loop, int flags);
    void ev_unloop (/*mixin(EV_P_)*/ ev_loop_t* loop, int how); /* set to 1 to break out of event loop, set to 2 to break out of all event loops */
}

/*
 * ref/unref can be used to add or remove a refcount on the mainloop. every watcher
 * keeps one reference. if you have a long-running watcher you never unregister that
 * should not keep ev_loop from running, unref() after starting, and ref() before stopping.
 */
void ev_ref   (/*mixin(EV_P)*/ ev_loop_t* loop);
void ev_unref (/*mixin(EV_P)*/ ev_loop_t* loop);

/*
 * convenience function, wait for a single event, without registering an event watcher
 * if timeout is < 0, do wait indefinitely
 */
void ev_once (/*mixin(EV_P_)*/ ev_loop_t* loop, int fd, int events, ev_tstamp timeout, void function(int revents, void* arg), void *arg);

version(ENABLE_ADDITIONAL_FEATURES)
{
    version(LIBEV4)
    {
        uint ev_iteration (/*mixin(EV_P)*/ ev_loop_t* loop); /* number of loop iterations */
        uint ev_depth     (/*mixin(EV_P)*/ ev_loop_t* loop); /* #ev_loop enters - #ev_loop leaves */
        void ev_verify    (/*mixin(EV_P)*/ ev_loop_t* loop); /* abort if loop data corrupted */
    }
    else
    {
        uint ev_loop_count  (/*mixin(EV_P)*/ ev_loop_t* loop); /* number of loop iterations */
        uint ev_loop_depth  (/*mixin(EV_P)*/ ev_loop_t* loop); /* #ev_loop_t enters - #ev_loop_t leaves */
        void ev_loop_verify (/*mixin(EV_P)*/ ev_loop_t* loop); /* abort if loop data corrupted */
    }
    
    void ev_set_io_collect_interval (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_tstamp interval); /* sleep at least this time, default 0 */
    void ev_set_timeout_collect_interval (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_tstamp interval); /* sleep at least this time, default 0 */
    
    /* advanced stuff for threading etc. support, see docs */
    void ev_set_userdata (/*mixin(EV_P_)*/ ev_loop_t* loop, void *data);
    void *ev_userdata (/*mixin(EV_P)*/ ev_loop_t* loop);
    void ev_set_invoke_pending_cb (/*mixin(EV_P_)*/ ev_loop_t* loop, void function(/*mixin(EV_P)*/ ev_loop_t* loop) invoke_pending_cb);
    void ev_set_loop_release_cb (/*mixin(EV_P_)*/ ev_loop_t* loop, void function(/*mixin(EV_P)*/ ev_loop_t* loop) release, void function(/*mixin(EV_P)*/ ev_loop_t* loop) acquire);
    
    uint ev_pending_count (/*mixin(EV_P)*/ ev_loop_t* loop); /* number of pending events, if any */
    void ev_invoke_pending (/*mixin(EV_P)*/ ev_loop_t* loop); /* invoke all pending watchers */
    
    /*
     * stop/start the timer handling.
     */
    void ev_suspend (/*mixin(EV_P)*/ ev_loop_t* loop);
    void ev_resume  (/*mixin(EV_P)*/ ev_loop_t* loop);
}

/* these may evaluate ev multiple times, and the other arguments at most once */
/* either use ev_init + ev_TYPE_set, or the ev_TYPE_init macro, below, to first initialise a watcher */
void ev_init(TYPE)(TYPE* w, void function(ev_loop_t*, TYPE*, int) cb)
{
    w.active = 0;
    w.pending = 0;
    ev_set_priority(w, 0);
    ev_set_cb(w, cb);
}
void ev_io_set(ev_io* w, int fd, int events)
{
        w.fd = fd;
        w.events = events | EV__IOFDSET;
}
void ev_timer_set(ev_timer* w, ev_tstamp after, ev_tstamp repeat)
{
        w.at = after;
        w.repeat = repeat;
}
void ev_periodic_set(ev_periodic* w, ev_tstamp ofs, ev_tstamp ival,
                ev_tstamp function(ev_periodic *w, ev_tstamp now) res)
{
        w.offset = ofs;
        w.interval = ival;
        w.reschedule_cb = res;
}
void ev_signal_set(ev_signal* w, int signum)
{
        w.signum = signum;
}
void ev_child_set(ev_child* w, int pid, int trace)
{
        w.pid = pid;
        w.flags = !!trace;
}
void ev_stat_set(ev_stat* w, char* path, ev_tstamp interval)
{
        w.path = path;
        w.interval = interval;
        w.wd = -2;
}
void ev_idle_set(ev_idle* w) /* nop, yes, this is a serious in-joke */
{
}
void ev_prepare_set(ev_prepare* w) /* nop, yes, this is a serious in-joke */
{
}
void ev_check_set(ev_check* w) /* nop, yes, this is a serious in-joke */
{
}
void ev_embed_set(ev_embed* w, ev_loop_t* other)
{
        w.other = other;
}
void ev_fork_set(ev_fork* w) /* nop, yes, this is a serious in-joke */
{
}
version(LIBEV4)
{
    version(EV_CLEANUP_ENABLE)
    {
        void ev_cleanup_set(ev_cleanup* w){}; /* nop, yes, this is a serious in-joke */
    }            
}
void ev_async_set(ev_async* w) /* nop, yes, this is a serious in-joke */
{
}
void ev_io_init(ev_io* w, void function(ev_loop_t*, ev_io*, int) cb, int fd,
        int events)
{
    ev_init(w, cb);
    ev_io_set(w, fd, events);
}
void ev_timer_init(ev_timer* w, void function(ev_loop_t*, ev_timer*, int) cb,
        ev_tstamp after, ev_tstamp repeat)
{
    ev_init(w, cb);
    ev_timer_set(w, after, repeat);
}
void ev_periodic_init(ev_periodic* w,
        void function(ev_loop_t*, ev_periodic*, int) cb,
        ev_tstamp ofs, ev_tstamp ival,
        ev_tstamp function(ev_periodic *w, ev_tstamp now) res)
{
    ev_init(w, cb);
    ev_periodic_set(w, ofs, ival, res);
}
void ev_signal_init(ev_signal* w, void function(ev_loop_t*, ev_signal*, int) cb,
        int signum)
{
    ev_init(w, cb);
    ev_signal_set(w, signum);
}
void ev_child_init(ev_child* w, void function(ev_loop_t*, ev_child*, int) cb,
        int pid, int trace)
{
    ev_init(w, cb);
    ev_child_set(w, pid, trace);
}
void ev_stat_init(ev_stat* w, void function(ev_loop_t*, ev_stat*, int) cb,
        char* path, ev_tstamp interval)
{
    ev_init(w, cb);
    ev_stat_set(w, path, interval);
}
void ev_idle_init(ev_idle* w, void function(ev_loop_t*, ev_idle*, int) cb)
{
    ev_init(w, cb);
    ev_idle_set(w);
}
void ev_prepare_init(ev_prepare* w,
        void function(ev_loop_t*, ev_prepare*, int) cb)
{
    ev_init(w, cb);
    ev_prepare_set(w);
}
void ev_check_init(ev_check* w, void function(ev_loop_t*, ev_check*, int) cb)
{
    ev_init(w, cb);
    ev_check_set(w);
}
void ev_embed_init(ev_embed* w, void function(ev_loop_t*, ev_embed*, int) cb,
        ev_loop_t* other)
{
    ev_init(w, cb);
    ev_embed_set(w, other);
}
void ev_fork_init(ev_fork* w, void function(ev_loop_t*, ev_fork*, int) cb)
{
    ev_init(w, cb);
    ev_fork_set(w);
}
version(LIBEV4)
{
    version(EV_CLEANUP_ENABLE)
    {
        void ev_cleanup_init(ev_cleanup* w, void function(ev_loop_t*, ev_cleanup*, int) cb)
        {
            ev_init(w, cb);
            ev_cleanup_set(w);
        }
    }
}
void ev_async_init(ev_async* w, void function(ev_loop_t*, ev_async*, int) cb)
{
    ev_init(w, cb);
    ev_async_set(w);
}
bool ev_is_pending(TYPE)(TYPE* w)
{
    return cast (bool) w.pending;
}
bool ev_is_active(TYPE)(TYPE* w)
{
    return cast (bool) w.active;
}
void function(ev_loop_t*, TYPE*, int) ev_cb(TYPE)(TYPE* w)
{
    return w.cb;
}

static if(EV_MINPRI == EV_MAXPRI)
{
    int ev_priority(TYPE)(TYPE* w)
    {
        return EV_MINPRI;
    }
    void ev_set_priority(TYPE)(TYPE* w, int pri)
    {
    }
}
else
{
    int ev_priority(TYPE)(TYPE* w)
    {
        return w.priority;
    }
    void ev_set_priority(TYPE)(TYPE* w, int pri)
    {
        static if(__traits(compiles, w.priority))
            w.priority = pri;
    }
}
ev_tstamp ev_periodic_at(ev_watcher_time* ev)
{
    return ev.at;
}

void ev_set_cb(TYPE)(TYPE* w,
        void function(ev_loop_t*, TYPE*, int) cb)
{
    w.cb = cb;
}

/* feeds an event into a watcher as if the event actually occured */
/* accepts any ev_watcher type */
void ev_feed_event     (/*mixin(EV_P_)*/ ev_loop_t* loop, void *w, int revents);
void ev_feed_fd_event  (/*mixin(EV_P_)*/ ev_loop_t* loop, int fd, int revents);
version(EV_SIGNAL_ENABLE)
{
    version(LIBEV4)
    {
        void ev_feed_signal    (int signum);
    }
    void ev_feed_signal_event (/*mixin(EV_P_)*/ ev_loop_t* loop, int signum);
}
void ev_invoke         (/*mixin(EV_P_)*/ ev_loop_t* loop, void *w, int revents);
int  ev_clear_pending  (/*mixin(EV_P_)*/ ev_loop_t* loop, void *w);

void ev_io_start       (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_io *w);
void ev_io_stop        (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_io *w);

void ev_timer_start    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_timer *w);
void ev_timer_stop     (/*mixin(EV_P_)*/ ev_loop_t* loop,ev_timer *w);
/* stops if active and no repeat, restarts if active and repeating, starts if inactive and repeating */
void ev_timer_again    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_timer *w);
/* return remaining time */
ev_tstamp ev_timer_remaining (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_timer *w);

version(EV_PERIODIC_ENABLE)
{
    void ev_periodic_start (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_periodic *w);
    void ev_periodic_stop  (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_periodic *w);
    void ev_periodic_again (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_periodic *w);
}

version(EV_SIGNAL_ENABLE)
{
    /* only supported in the default loop */
    void ev_signal_start   (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_signal *w);
    void ev_signal_stop    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_signal *w);
}
version(EV_CHILD_ENABLE)
{
    /* only supported in the default loop */
    void ev_child_start    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_child *w);
    void ev_child_stop     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_child *w);
}
version(EV_STAT_ENABLE)
{
    void ev_stat_start     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_stat *w);
    void ev_stat_stop      (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_stat *w);
    void ev_stat_stat      (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_stat *w);
}

version(EV_IDLE_ENABLE)
{
    void ev_idle_start     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_idle *w);
    void ev_idle_stop      (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_idle *w);
}
version(EV_PREPARE_ENABLE)
{
    void ev_prepare_start  (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_prepare *w);
    void ev_prepare_stop   (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_prepare *w);
}
version(EV_CHECK_ENABLE)
{
    void ev_check_start    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_check *w);
    void ev_check_stop     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_check *w);
}
version(EV_FORK_ENABLE)
{
    void ev_fork_start     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_fork *w);
    void ev_fork_stop      (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_fork *w);
}

version(LIBEV4)
{
    version(EV_CLEANUP_ENABLE)
    {
        void ev_cleanup_start  (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_cleanup *w);
        void ev_cleanup_stop   (/*mixin(EV_P_)*/ ev_loop_t* loop,ev_cleanup *w);
    }
}

version(EV_EMBED_ENABLE)
{
    /* only supported when loop to be embedded is in fact embeddable */
    void ev_embed_start    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_embed *w);
    void ev_embed_stop     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_embed *w);
    void ev_embed_sweep    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_embed *w);
}

version(EV_ASYNC_ENABLE)
{
    void ev_async_start    (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_async *w);
    void ev_async_stop     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_async *w);
    void ev_async_send     (/*mixin(EV_P_)*/ ev_loop_t* loop, ev_async *w);
}

version(LIBEV4)
{
    version(LIBEV3_COMPAT)
    {
        alias EVRUN_NOWAIT EVLOOP_NONBLOCK; 
        alias EVRUN_ONCE EVLOOP_ONESHOT;
        alias EVBREAK_CANCEL EVUNLOOP_CANCEL;
        alias EVBREAK_ONE EVUNLOOP_ONE;
        alias EVBREAK_ALL EVUNLOOP_ALL;
        alias ev_run ev_loop;
        alias ev_break ev_unloop;
        alias ev_loop_destroy ev_default_destroy;
        alias ev_loop_fork ev_default_fork;
        version(ENABLE_ADDITIONAL_FEATURES)
        {
            alias ev_iteration ev_loop_count;
            alias ev_depth ev_loop_depth;
            alias ev_verify ev_loop_verify;
        }
    }
}
