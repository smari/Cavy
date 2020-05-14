#scope_file
#import "Basic";
#import "Thread";

#scope_export


ThreadPoolHandler :: #type (task: *void) -> s64;

ThreadPool :: struct {
    threads         : [..]*Thread;
    // TODO: Generalize and polymorphize task type.
    // TODO: tasks should be a queue, for speed.
    tasks           : [..]*HTTPClientConnection;
    task_mutex      : Mutex;
    work_available  : Condition;
    task_handler    : ThreadPoolHandler;
    num_threads     : int = 10;
}

threadpool_task_add :: (pool: *ThreadPool, task: *HTTPClientConnection) {
    lock(*pool.task_mutex);
    array_add(*pool.tasks, task);
    signal(*pool.work_available);
    unlock(*pool.task_mutex);
}

threadpool_task_get :: (thread: *Thread, pool: *ThreadPool) -> *HTTPClientConnection, bool {
    got_work := false;
    task : *HTTPClientConnection;

    lock(*pool.task_mutex);
    if pool.tasks.count > 0 {
        task = pool.tasks[0];
        array_ordered_remove_by_index(*pool.tasks, 0);
        got_work = true;
    }
    unlock(*pool.task_mutex);
    return task, got_work;
}

threadpool_thread_runner :: (thread: *Thread) -> s64 {
    // Here we wait for tasks and execute them as needed.
    // TODO: We'd like to be able to pass along the polymorphism here. - smari 12020-05-13
    pool: *ThreadPool = cast(*ThreadPool) thread.data;

    // Set up temporary storage for this thread:
    ts: Temporary_Storage;
    context.temporary_storage = *ts;

    while true {
        wait_for(*pool.work_available);
        client, found := threadpool_task_get(thread, pool);
        if found threadpool_task_process(client);
    }
    return 0;
}

threadpool_start :: (using pool: *ThreadPool) {
    init(*pool.task_mutex);
    init(*pool.work_available);
    array_reset(*pool.tasks);
    for 1..num_threads {
        t := New(Thread);
        t.data = pool;
        thread_init(t, threadpool_thread_runner);
        array_add(*threads, t);
        thread_start(t);
    }
}
