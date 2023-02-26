const std = @import("std");
const parser = @import("parser.zig");
test "all tests" {
    std.testing.refAllDecls(parser);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    _ = args.skip();
    const src_path = args.next() orelse return error.NoSourceFileArg;

    const f = try std.fs.cwd().openFile(src_path, .{});
    defer f.close();

    const src = try f.readToEndAlloc(alloc, 1024 * 100);

    try parser.parse(alloc, src);
}
