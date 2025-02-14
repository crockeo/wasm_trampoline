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

    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        std.debug.print("=== {s} ===\n", .{entry.basename});

        const content = try entry.dir.readFileAllocOptions(
            allocator,
            entry.path,
            std.math.maxInt(usize),
            null,
            2,
            0,
        );
        defer allocator.free(content);

        try process_file(allocator, output_file, content);
    }
}

fn process_file(allocator: std.mem.Allocator, _: std.fs.File, content: [:0]const u8) !void {
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
        const return_type_name = get_node_str(content, &tree, fn_proto.ast.return_type);

        // TODO: use this information to generate a pair of functions
        // - One on the Javascript side, which will accept an object and call into this function.
        //
        // - One on the Zig side, which will accept the Javascript string,
        //   parse the JSON into an actual object,
        //   pass it to the inner implementation,
        //   and then do the reverse to get it back to Javascript.
        for (type_names.items) |type_name| {
            std.debug.print("{s} ", .{type_name});
        }
        std.debug.print("-> {s}\n", .{return_type_name});
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

fn print_token(content: []const u8, tree: *const std.zig.Ast, token: std.zig.Ast.TokenIndex) void {
    const token_starts = tree.tokens.items(.start);

    const start = token_starts[token];
    const end = token_starts[token + 1];
    std.debug.print("{s}\n", .{content[start..end]});
}
