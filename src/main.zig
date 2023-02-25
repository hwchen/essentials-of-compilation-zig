const std = @import("std");
const parser = @import("parser.zig");
test "all tests" {
    std.testing.refAllDecls(parser);
}

pub fn main() !void {}
