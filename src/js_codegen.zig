const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip the filename
    const file_arg = args.next() orelse {
        std.debug.print("ERROR: no output file argument provided.\n", .{});
        return;
    };

    try generate_trampoline(file_arg);
}

/// `generate_trampoline` creates a Javascript file
/// which allows JS to call a Zig function with a complex object.
fn generate_trampoline(output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    const writer = file.writer();

    const lines = [_][]const u8{
        "function callZigWasm(module, func, object) {\n",
        "    let encoder = TextEncoder();\n",
        "    let encodedString = encoder.encode(JSON.stringify(object));\n",
        "    let buf = new Uint8Array(module.instance.exports);\n",
        "    buf.set(encodedString);\n",
        "    module.exports[func](buf.byteLength);\n",
        "}\n",
    };
    for (lines) |line| {
        try writer.writeAll(line);
    }
}
