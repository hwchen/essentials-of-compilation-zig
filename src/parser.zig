const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const dre = @import("dre");
const zacc = @import("zacc");

const Token = enum {
    print,
    input_int,

    ident,
    number,
    @"+",
    @"-",
    @"=",
    @"(",
    @")",
    @";",

    sentinel, // End of string
    invalid, // Invalid token
};

const Lexer = dre.Lexer(Token, .{
    ._ignore = "[ \t\n]+",

    .print = "print",
    .input_int = "input_int",

    .ident = "[a-zA-Z]+",
    .number = "[0-9]+",
    .@"+" = "%+",
    .@"-" = "-",
    .@"=" = "=",
    .@"(" = "%(",
    .@")" = "%)",
    .@";" = ";",
});

test "smoke test lexer" {
    var toks = Lexer.init("a = 1 + (input_int() - 3);");

    const expect = [_]Token{
        .ident,
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
        .@";",
        .sentinel,
    };

    for (expect) |tok| {
        try std.testing.expectEqual(tok, toks.next());
    }
}

const Parser = blk: {
    @setEvalBranchQuota(100000);
    break :blk zacc.Parser(Token,
        \\ start = stmts $;
        \\ stmts = stmts stmt | stmt;
        \\ stmt = .ident '=' exp ';'
        \\      | .print '(' exp ')' ';'
        \\      | exp ';' ;
        \\ exp = .ident
        \\     | .number
        \\     | .input_int '(' ')'
        \\     | '-' exp
        \\     | exp '+' exp
        \\     | exp '-' exp
        \\     | '(' exp ')';
    );
};

/// Caller must call deinit on Ast
pub fn parse(alloc: Allocator, input: []const u8) !Ast {
    var toks = Lexer.init(input);
    var ast = Ast.init(alloc);
    _ = try Parser.parse(alloc, &toks, Context{ .toks = &toks, .ast = &ast });
    return ast;
}

pub fn parseConcrete(alloc: Allocator, input: []const u8) !void {
    var toks = Lexer.init(input);
    const tree = try Parser.parseToTree(alloc, &toks);
    defer tree.deinit(alloc);
    try std.io.getStdOut().writer().print("{}\n", .{tree.fmtDot()});
}

pub const Context = struct {
    toks: *Lexer,
    ast: *Ast,

    /// These variants are needed when walking the tree,
    /// building towards the root by turning children into
    /// Ast nodes.
    ///
    /// Then at the top, when we get to a parser node `stmts`,
    /// we just append the children `stmt` into the ast.
    pub const Result = union(enum) {
        stmts,
        stmt: Ast.Stmt,
        exp: Ast.Exp,
        opcode: Ast.OpCode,
        ident: []const u8,
        print,
        input_int,
        @"=", // to know if there's an assignment
        @"(", // to know when group starts
        unused,

        pub fn deinit(_: Result, _: Allocator) void {}
    };

    pub fn nonTerminal(self: Context, nt: Parser.NonTerminal, children: []const Result) !Result {
        return switch (nt) {
            .start => unreachable,
            .stmts => blk: {
                for (children) |child| {
                    switch (child) {
                        .stmt => |stmt| try self.ast.stmts.append(stmt),
                        else => {},
                    }
                }
                break :blk .stmts;
            },
            .stmt => switch (children[0]) {
                .print => .{ .stmt = Ast.Stmt{ .print = @field(children[2], "exp") } },
                .exp => .{ .stmt = Ast.Stmt{ .expr = @field(children[0], "exp") } },
                .ident => |s| .{ .stmt = Ast.Stmt{ .assign = .{ .variable = s, .expr = @field(children[2], "exp") } } },
                else => Result.unused,
            },
            .exp => if (children.len > 1 and std.meta.isTag(children[1], "opcode")) blk: {
                // Binary op
                const lhs_ptr = try self.ast.arena.allocator().create(Ast.Exp);
                lhs_ptr.* = @field(children[0], "exp");
                const rhs_ptr = try self.ast.arena.allocator().create(Ast.Exp);
                rhs_ptr.* = @field(children[2], "exp");

                break :blk .{ .exp = .{ .binary_op = .{ .lhs = lhs_ptr, .op = @field(children[1], "opcode"), .rhs = rhs_ptr } } };
            } else switch (children[0]) {
                .opcode => |op| blk: {
                    // Unary op
                    const expr_ptr = try self.ast.arena.allocator().create(Ast.Exp);
                    expr_ptr.* = @field(children[1], "exp");

                    break :blk .{ .exp = .{ .unary_op = .{ .op = op, .expr = expr_ptr } } };
                },
                .@"(" => blk: {
                    // Group
                    const expr_ptr = try self.ast.arena.allocator().create(Ast.Exp);
                    expr_ptr.* = @field(children[1], "exp");

                    break :blk .{ .exp = .{ .group = expr_ptr } };
                },
                .input_int => .{ .exp = .input_int },

                // ident and number
                else => children[0],
            },
        };
    }

    pub fn terminal(self: Context, token: Token) !Result {
        return switch (token) {
            .print => .print,
            .input_int => .input_int,
            .ident => .{ .ident = self.toks.str() },
            .number => .{ .exp = .{ .number = try std.fmt.parseInt(i64, self.toks.str(), 10) } },
            .@"+" => .{ .opcode = Ast.OpCode.add },
            .@"-" => .{ .opcode = Ast.OpCode.sub },
            .@"=" => .@"=",
            .@"(" => .@"(",
            else => .unused,
        };
    }
};

pub const Ast = struct {
    arena: std.heap.ArenaAllocator,
    stmts: ArrayList(Stmt),

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return .{
            .arena = std.heap.ArenaAllocator.init(alloc),
            .stmts = ArrayList(Stmt).init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    pub const Stmt = union(enum) {
        print: Exp,
        expr: Exp,
        assign: struct {
            variable: []const u8,
            expr: Exp,
        },
    };

    pub const Exp = union(enum) {
        number: i64,
        variable: []const u8,
        binary_op: struct {
            lhs: *Exp,
            op: OpCode,
            rhs: *Exp,
        },
        unary_op: struct {
            op: OpCode,
            expr: *Exp,
        },
        group: *Exp,
        input_int,
    };

    pub const OpCode = union(enum) {
        add,
        sub,
    };
};
