const std = @import("std");
const dre = @import("dre");

const Token = enum {
    word,
    number,
    plus,
    minus,
    eql,
    lparen,
    rparen,

    sentinel, // End of string
    invalid, // Invalid token
};

const Lexer = dre.Lexer(Token, .{
    ._ignore = "[ \t\n]+",

    .word = "[a-zA-Z]+",
    .number = "[0-9]+",
    .plus = "%+",
    .minus = "-",
    .eql = "=",
    .lparen = "%(",
    .rparen = "%)",
});

test "smoke test lexer" {
    var toks = Lexer.init("const a = 1 + (2 - 3)");

    const expect = [_]Token{
        .word,
        .word,
        .eql,
        .number,
        .plus,
        .lparen,
        .number,
        .minus,
        .number,
        .rparen,
        .sentinel,
    };

    for (expect) |tok| {
        try std.testing.expectEqual(tok, toks.next());
    }
}
