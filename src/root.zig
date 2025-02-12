const std = @import("std");
const testing = std.testing;

var wasm_allocator = std.heap.WasmAllocator{};
const global_allocator = std.mem.Allocator{
    .ptr = @ptrCast(&wasm_allocator),
    .vtable = &std.heap.WasmAllocator.vtable,
};

export fn allocate(width: usize) *anyopaque {
    var slice = global_allocator.alloc(u8, width) catch unreachable;
    return @ptrCast(&slice);
}

export fn free(ptr: *anyopaque, width: usize) void {
    const slice_ptr: [*]u8 = @alignCast(@ptrCast(ptr));
    const slice = slice_ptr[0..width];
    global_allocator.free(slice);
}

const MemorySegment = extern struct {
    ptr: *anyopaque,
    width: usize,
};

export fn do_something(req_segment: MemorySegment) MemorySegment {
    const req = trampoline_deserialize(
        DoSomethingReq,
        global_allocator,
        req_segment.ptr,
        req_segment.width,
    ) catch unreachable;
    defer req.deinit();

    const res = do_something_inner(req.value) catch unreachable;

    const raw_res = trampoline_serialize(global_allocator, res) catch unreachable;
    return raw_res;
}

const DoSomethingReq = struct {};
const DoSomethingRes = struct {};

fn do_something_inner(req: DoSomethingReq) !DoSomethingRes {
    _ = req;
    return DoSomethingRes{};
}

fn trampoline_deserialize(
    comptime T: type,
    allocator: std.mem.Allocator,
    ptr: *anyopaque,
    width: usize,
) !std.json.Parsed(T) {
    const slice = @as([*]u8, @alignCast(@ptrCast(ptr)))[0..width];
    return try std.json.parseFromSlice(T, allocator, slice, .{});
}

fn trampoline_serialize(
    allocator: std.mem.Allocator,
    value: anytype,
) !MemorySegment {
    const slice = try std.json.stringifyAlloc(allocator, value, .{});
    return .{
        .ptr = @ptrCast(slice),
        .width = slice.len,
    };
}

fn main() void {}
