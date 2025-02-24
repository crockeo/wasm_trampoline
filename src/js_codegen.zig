const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip the filename
    const output_file_arg = args.next() orelse {
        std.debug.print("ERROR: no output file argument provided.\n", .{});
        return;
    };
    const output_file = try std.fs.cwd().createFile(output_file_arg, .{});

    const src_root_arg = args.next() orelse {
        std.debug.print("ERROR: no source root argument provided.\n", .{});
        return;
    };
    var src_root = try std.fs.cwd().openDir(src_root_arg, .{ .iterate = true });
    defer src_root.close();

    var walker = try src_root.walk(allocator);
    defer walker.deinit();

    try output_file.writeAll("const std = @import(\"std\");\n\n");
    try output_file.writeAll(
        \\var wasm_allocator = std.heap.WasmAllocator{};
        \\const global_allocator = std.mem.Allocator{
        \\    .ptr = @ptrCast(&wasm_allocator),
        \\    .vtable = &std.heap.WasmAllocator.vtable,
        \\};
        \\
        \\
    );

    try output_file.writeAll(
        \\extern fn native_console_log(message: [*]const u8, len: usize) void;
        \\fn console_log(message: []const u8) void {
        \\    native_console_log(message.ptr, message.len);
        \\}
        \\
        \\const ConsoleWriterCtx = struct {};
        \\const ConsoleWriterError = error{};
        \\
        \\fn console_writer_writefn(_: ConsoleWriterCtx, bytes: []const u8) ConsoleWriterError!usize {
        \\    console_log(bytes);
        \\    return bytes.len;
        \\}
        \\const ConsoleWriter = std.io.Writer(
        \\    ConsoleWriterCtx,
        \\    ConsoleWriterError,
        \\    console_writer_writefn,
        \\);
        \\const console_writer = ConsoleWriter{ .context = .{} };
        \\
        \\
    );

    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        std.debug.print("=== {s} ===\n", .{entry.basename});

        // TODO: make `module_name` unique by tagging this with an index,
        // so that 2 modules of the same name (but different paths)
        // don't get clobbered.
        //
        // TODO: make it so we import the full name of the path,
        // not the basename.
        // b/c sometimes things will be nested into other directories
        const suffix_start = std.mem.indexOf(u8, entry.basename, ".") orelse unreachable;
        const module_name = entry.basename[0..suffix_start];
        try std.fmt.format(output_file.writer(), "const {s} = @import(\"{s}\");\n", .{
            module_name,
            entry.basename,
        });

        const content = try entry.dir.readFileAllocOptions(
            allocator,
            entry.path,
            std.math.maxInt(usize),
            null,
            2,
            0,
        );
        defer allocator.free(content);

        try process_file(allocator, output_file, module_name, content);
    }
}

fn process_file(
    allocator: std.mem.Allocator,
    output_file: std.fs.File,
    module_name: []const u8,
    content: [:0]const u8,
) !void {
    var tree = try std.zig.Ast.parse(allocator, content, .zig);
    defer tree.deinit(allocator);

    for (tree.rootDecls()) |decl_idx| {
        var fn_proto_buf: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = std.zig.Ast.fullFnProto(tree, &fn_proto_buf, decl_idx) orelse continue;

        var params = fn_proto.iterate(&tree);

        const first_param = params.next() orelse continue;
        if (!is_wasm_sentinel(content, &tree, &first_param)) {
            continue;
        }

        var type_names = std.ArrayList([]const u8).init(allocator);
        while (params.next()) |param| {
            const type_name = get_node_str(content, &tree, param.type_expr);
            try type_names.append(type_name);
        }

        // TODO: generate the javascript-side trampoline function
        //
        // TODO: parse the function name and pass it below in place of the "TODO"
        const trampoline_function = try generate_trampoline_function(
            allocator,
            module_name,
            "TODO",
            type_names,
        );
        defer allocator.free(trampoline_function);
        try output_file.writeAll(trampoline_function);
    }
}

fn is_wasm_sentinel(
    content: []const u8,
    tree: *const std.zig.Ast,
    param: *const std.zig.Ast.full.FnProto.Param,
) bool {
    const name_token = param.name_token orelse return false;
    const param_name = get_token_str(
        content,
        tree,
        name_token,
        name_token,
    );
    const type_name = get_token_str(
        content,
        tree,
        tree.nodes.get(param.type_expr).main_token,
        tree.lastToken(param.type_expr),
    );
    return (std.mem.eql(u8, param_name, "_") and std.mem.eql(u8, type_name, "WasmMe"));
}

fn get_node_str(
    content: []const u8,
    tree: *const std.zig.Ast,
    node: std.zig.Ast.Node.Index,
) []const u8 {
    return get_token_str(
        content,
        tree,
        tree.nodes.get(node).main_token,
        tree.lastToken(node),
    );
}

fn get_token_str(
    content: []const u8,
    tree: *const std.zig.Ast,
    start_token: std.zig.Ast.TokenIndex,
    end_token: std.zig.Ast.TokenIndex,
) []const u8 {
    const starts = tree.tokens.items(.start);
    const segment_start = starts[start_token];
    const segment_end = starts[end_token + 1];
    return content[segment_start..segment_end];
}

fn generate_trampoline_function(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    function_name: []const u8,
    type_names: std.ArrayList([]const u8),
) ![]const u8 {
    // TODO: for this function, don't use the type names for arg names.
    // instead give each argument its own index (e.g. arg0)
    // so that they're unique, even if you're passing multiples
    // of the same value
    var buf_writer = BufWriter.init(allocator);

    try buf_writer.format("export fn wasm_trampoline_{s}(", .{function_name});

    var i: usize = 0;
    for (type_names.items) |type_name| {
        var prefix: []const u8 = undefined;
        if (i == 0) {
            prefix = "";
        } else {
            prefix = ", ";
        }
        try buf_writer.format("{0s}{1s}_ptr: [*]const u8, {1s}_width: usize", .{ prefix, type_name });
        i += 1;
    }

    try buf_writer.format(") [*c]const u8 {{\n", .{});
    for (type_names.items) |type_name| {
        try buf_writer.format(
            \\    const {1s}_slice = {1s}_ptr[0..{1s}_width];
            \\    const {1s}_req = std.json.parse_from_slice({0s}.{1s}, global_allocator, {1s}_slice, .{{}}) catch |err| {{
            \\        std.fmt.format(console_writer, "{{}}", .{{err}}) catch {{}};
            \\        unreachable;
            \\    }};
            \\    defer {1s}_req.deinit();
            \\
        ,
            .{
                module_name,
                type_name,
            },
        );
    }

    try buf_writer.format("    const res = {0s}(WasmMe{{}}", .{function_name});
    for (type_names.items) |type_name| {
        try buf_writer.format(", {0s}_req", .{type_name});
    }
    try buf_writer.format(
        \\) catch |err| {{
        \\        std.fmt.format(console_writer, "{{}}", .{{err}});
        \\        unreachable;
        \\    }};
        \\    const res_slice = std.json.stringifyAlloc(global_allocator, res, .{{}}) catch |err| {{
        \\        std.format.format(console_writer, "{{}}", .{{err}}) catch {{}};
        \\        unreachable;
        \\    }};
        \\    global_allocator.free(res_slice);
        \\
        \\    var null_terminated_res_slice = global_allocator.alloc(u8, res_slice.len + 1) catch @panic("OOM");
        \\    std.mem.copyForwards(u8, null_terminated_res_slice, res_slice);
        \\    null_terminated_res_slice[null_terminated_res_slice.len - 1] = 0;
        \\    return @ptrCast(null_terminated_res_slice);
        \\}}
        \\
    , .{});

    return try buf_writer.toOwnedSlice();
}

const BufWriter = struct {
    const Self = @This();

    const Error = std.mem.Allocator.Error;

    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn write(self: *Self, data: []const u8) Self.Error!usize {
        try self.buf.appendSlice(data);
        return data.len;
    }

    pub fn toOwnedSlice(self: *Self) Self.Error![]const u8 {
        return self.buf.toOwnedSlice();
    }

    pub fn format(self: *Self, comptime fmt: []const u8, args: anytype) Self.Error!void {
        const writer: std.io.Writer(*Self, Self.Error, Self.write) = .{ .context = self };
        try std.fmt.format(writer, fmt, args);
    }
};
