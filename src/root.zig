const std = @import("std");
const testing = std.testing;

var wasm_allocator = std.heap.WasmAllocator{};
const global_allocator = std.mem.Allocator{
    .ptr = @ptrCast(&wasm_allocator),
    .vtable = &std.heap.WasmAllocator.vtable,
};

export fn allocate(width: usize) *anyopaque {
    const slice = global_allocator.alloc(u8, width) catch unreachable;
    return @ptrCast(slice.ptr);
}

export fn free(ptr: *anyopaque, width: usize) void {
    const slice_ptr: [*]u8 = @alignCast(@ptrCast(ptr));
    const slice = slice_ptr[0..width];
    global_allocator.free(slice);
}

export fn do_something(ptr: [*]const u8, width: usize) [*c]const u8 {
    const slice = ptr[0..width];
    const req = std.json.parseFromSlice(DoSomethingReq, global_allocator, slice, .{}) catch |err| {
        std.fmt.format(console_writer, "{}", .{err}) catch {};
        unreachable;
    };
    defer req.deinit();

    const res = do_something_inner(req.value) catch unreachable;

    const res_slice = std.json.stringifyAlloc(global_allocator, res, .{}) catch |err| {
        std.fmt.format(console_writer, "{}", .{err}) catch {};
        unreachable;
    };
    defer global_allocator.free(res_slice);

    const null_terminated_res_slice = global_allocator.alloc(u8, res_slice.len + 1) catch @panic("OOM");
    std.mem.copyForwards(u8, null_terminated_res_slice, res_slice);
    null_terminated_res_slice[null_terminated_res_slice.len - 1] = 0;
    return @ptrCast(null_terminated_res_slice);
}

const DoSomethingReq = struct {};
const DoSomethingRes = struct {
    the_meaning: usize,
};

fn do_something_inner(req: DoSomethingReq) !DoSomethingRes {
    _ = req;
    return DoSomethingRes{
        .the_meaning = 42,
    };
}

// Tools to write to console.log from WASM.
// Requires that someone provides this `native_console_log` function
// from inside of WASM-land.
extern fn native_console_log(message: [*]const u8, len: usize) void;
fn console_log(message: []const u8) void {
    native_console_log(message.ptr, message.len);
}

// And then this is so we can write to console.log with ~fancy formatting~.
const ConsoleWriterCtx = struct {};
const ConsoleWriterError = error{};

fn console_writer_writefn(_: ConsoleWriterCtx, bytes: []const u8) ConsoleWriterError!usize {
    console_log(bytes);
    return bytes.len;
}
const ConsoleWriter = std.io.Writer(
    ConsoleWriterCtx,
    ConsoleWriterError,
    console_writer_writefn,
);
const console_writer = ConsoleWriter{ .context = .{} };
