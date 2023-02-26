const std = @import("std");
const Allocator = std.mem.Allocator;
const dre = @import("dre");
const zacc = @import("zacc");

const Token = enum {
    print,
    input_int,

    word,
    number,
    @"+",
    @"-",
    @"=",
    @"(",
    @")",

    sentinel, // End of string
    invalid, // Invalid token
};

const Lexer = dre.Lexer(Token, .{
    ._ignore = "[ \t\n]+",

    .print = "print",
    .input_int = "input_int",

    .word = "[a-zA-Z]+",
    .number = "[0-9]+",
    .@"+" = "%+",
    .@"-" = "-",
    .@"=" = "=",
    .@"(" = "%(",
    .@")" = "%)",
});

const Parser = blk: {
    @setEvalBranchQuota(100000);
    break :blk zacc.Parser(Token,
        \\ //start = program $
        \\ //program = stmt*
        \\ start = stmt $;
        \\ stmt = var '=' exp
        \\      | .print '(' exp ')'
        \\      | exp;
        \\ exp = var
        \\     | int
        \\     | .input_int '(' ')'
        \\     | '-' exp
        \\     | exp '+' exp
        \\     | exp '-' exp
        \\     | '(' exp ')';
        \\ var = .word;
        \\ int = .number;
    );
};

pub fn parse(alloc: Allocator, input: []const u8) !void {
    var toks = Lexer.init(input);
    const tree = try Parser.parseToTree(alloc, &toks);
    defer tree.deinit(alloc);
    try std.io.getStdOut().writer().print("{}\n", .{tree.fmtDot()});
}

test "smoke test lexer" {
    var toks = Lexer.init("a = 1 + (input_int() - 3)");

    const expect = [_]Token{
        .word,
        .word,
        .@"=",
        .number,
        .@"+",
        .@"(",
        .input_int,
        .@"(",
        .@")",
        .@"-",
        .number,
        .@")",
        .sentinel,
    };

    for (expect) |tok| {
        try std.testing.expectEqual(tok, toks.next());
    }
}
