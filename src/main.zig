const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;

fn charIsWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n' or char == ',' or char == ':';
}

const Expr = union(enum) {
    const Self = @This();

    list: []*Self,
    atom: []const u8,

    const ParseError = Allocator.Error || error{
        NoRightParen,
        NoRightQuote,
        EmptyString,
    };

    pub fn fromStr(str: []const u8, allocator: *Allocator) ParseError!*Self {
        return (try fromStrInternal(str, allocator)).expr;
    }

    const InternalFromStrRetType = struct {
        expr: *Self,
        index: usize,
    };

    fn fromStrInternal(str: []const u8, allocator: *Allocator) ParseError!InternalFromStrRetType {
        var expr = try allocator.create(Self);
        var str_i: usize = 0;
        while (str.len - str_i > 0 and charIsWhitespace(str[str_i]))
            str_i += 1;
        if (str.len - str_i == 0)
            return ParseError.EmptyString;
        return switch (str[str_i]) {
            // list
            '(' => parse: {
                const list_len = Self.getListLenFromStr(str);
                expr.* = Self{ .list = try allocator.alloc(*Self, list_len) };
                var current_index: usize = 1;
                var i: usize = 0;
                while (i < list_len and current_index < str.len) {
                    const result = try Self.fromStrInternal(str[current_index..], allocator);
                    expr.*.list[i] = result.expr;
                    current_index += result.index;
                    while (charIsWhitespace(str[current_index]))
                        current_index += 1;
                    if (str[current_index] == ')') {
                        break :parse InternalFromStrRetType{
                            .expr = expr,
                            .index = current_index + 1,
                        };
                    }
                    i += 1;
                }
                break :parse ParseError.NoRightParen;
            },
            // atom literal (with quotes)
            '"' => parse: {
                for (str[1..]) |char, i| {
                    if (char == '"') {
                        var atom = try allocator.*.alloc(u8, i);
                        for (str[1..i+1]) |atom_char, j|
                            atom[j] = atom_char;
                        expr.* = Self{ .atom = atom };
                        break :parse InternalFromStrRetType{
                            .expr = expr,
                            .index = i+2,
                        };
                    }
                }
                break :parse ParseError.NoRightQuote;
            },
            // atom (without quotes)
            else => parse: {
                var i: usize = 0;
                while (i < str.len and !charIsWhitespace(str[i]) and str[i] != ')')
                    i += 1;
                var atom = try allocator.*.alloc(u8, i);
                for (str[0..i]) |char, j|
                    atom[j] = char;
                expr.* = Self{ .atom = atom };
                break :parse InternalFromStrRetType{
                    .expr = expr,
                    .index = i,
                };
            },
        };
    }

    fn getListLenFromStr(str: []const u8) usize {
        var len: usize = 0;
        var in_quotes = false;
        var paren_depth: ?usize = null;
        var i: usize = 0;
        var met_first_paren = false;
        while (i < str.len and (charIsWhitespace(str[i]) or (!met_first_paren and str[i] == '('))) {
            if (str[i] == '(')
                met_first_paren = true;
            i += 1;
        }
        var last_char_was_whitespace = false;
        for (str[i..]) |char| {
            if (paren_depth) |depth| {
                switch (depth) {
                    '(' => paren_depth = depth + 1,
                    ')' => {
                        if (depth == 1) {
                            paren_depth = null;
                            len += 1;
                        }
                        paren_depth = depth - 1;
                    },
                    else => {},
                }
            } else if (in_quotes and char == '"') {
                in_quotes = false;
            } else if (char == '"') {
                in_quotes = true;
            } else if (charIsWhitespace(char) and !last_char_was_whitespace) {
                last_char_was_whitespace = true;
                len += 1;
            } else if (char == '(') {
                paren_depth = 1;
            } else if (char == ')') {
                len += 1;
                return len;
            }
            if (last_char_was_whitespace and !charIsWhitespace(char))
                last_char_was_whitespace = false;
        }
        return len;
    }

    pub fn toString(self: *const Self, allocator: *Allocator) Allocator.Error![]const u8 {
        const len = self.toStringLen();
        var out = try allocator.*.alloc(u8, len);
        var index: usize = 0;
        self.toStringInner(out, &index);
        return out;
    }

    fn toStringInner(self: *const Self, out: []u8, index: *usize) void {
        switch (self.*) {
            .list => |list| {
                out[index.*] = '(';
                index.* += 1;
                if (list.len > 0) {
                    list[0].toStringInner(out, index);
                    for (list[1..]) |child| {
                        out[index.*] = ' ';
                        index.* += 1;
                        child.toStringInner(out, index);
                    }
                }
                out[index.*] = ')';
                index.* += 1;
            },
            .atom => |atom| {
                for (atom) |char| {
                    out[index.*] = char;
                    index.* += 1;
                }
            },
        }
    }

    fn toStringLen(self: *const Self) usize {
        return switch (self.*) {
            .list => |list| len: {
                var len: usize = 1;
                for (list) |item|
                    len += item.toStringLen() + 1;
                break :len len;
            },
            .atom => |atom| atom.len,
        };
    }

    pub fn replace(self: *Self, replacements: *StringHashMap(Self)) void {
        if (eql(u8, @tagName(self.*), "list")) {
            for (self.*.list) |child| {
                switch (child.*) {
                    .list => child.replace(replacements),
                    .atom => |atom| {
                        if (replacements.get(atom)) |replacement|
                            child.* = replacement;
                    }
                }
            }
        }
    }
};

const Effect = union(enum) {
    const Self = @This();

    add_def: struct {
        name: []const u8,
        subst: Expr,
    },
    print: []const u8,
};

const State = struct {
    const Self = @This();

    defs: StringHashMap(Expr),
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .defs = StringHashMap(Expr).init(allocator.*),
            .allocator = allocator,
        };
    }

    const EvalError = Allocator.Error || @typeInfo(@typeInfo(@TypeOf(std.io.Reader(std.fs.File,std.os.ReadError,std.fs.File.read).readUntilDelimiterOrEofAlloc)).Fn.return_type.?).ErrorUnion.error_set || Expr.ParseError;

    pub fn eval(self: *const Self, expr: *Expr) EvalError![]const Effect {
        var effects = ArrayList(Effect).init(self.*.allocator.*);
        try self.evalInner(expr, &effects);
        return effects.toOwnedSlice();
    }

    fn evalInner(
        self: *const Self,
        expr: *Expr,
        effects: *ArrayList(Effect),
    ) EvalError!void {
        switch (expr.*) {
            Expr.list => |list| {
                for (list) |child| {
                    if (eql(u8, @tagName(child.*), "atom")) {
                        if (eql(u8, child.*.atom, "input")) {
                            const stdin_reader = std.io.getStdIn().reader();
                            const input = (try stdin_reader.readUntilDelimiterOrEofAlloc(self.*.allocator.*, '\n', (1 << 64) - 1)).?;
                            child.* = (try Expr.fromStr(input, self.*.allocator)).*;
                        }
                    }
                }
                for (list) |child| {
                    if (eql(u8, @tagName(child.*), "atom")) {
                        if (self.*.defs.get(child.*.atom)) |subst|
                            child.* = subst;
                    }
                    for (try self.eval(child)) |new_effect| {
                        try effects.append(new_effect);
                    }
                }
                if (list.len <= 1)
                    return;
                const func = list[0];
                switch (func.*) {
                    .list => |func_list| {
                        if (
                            func_list.len < 3 or
                            list.len < 3 or
                            !eql(u8, @tagName(func_list[0].*), "atom") or
                            !eql(u8, func_list[0].atom, "lambda") or
                            !eql(u8, @tagName(func_list[1].*), "list") or
                            func_list[1].list.len > list.len - 1
                        )
                            return;
                        const args = func_list[1].list;
                        var params = StringHashMap(Expr).init(self.*.allocator.*);
                        defer params.deinit();
                        var body = func_list[2..];
                        for (args) |arg, i|
                            _ = try params.getOrPutValue(arg.*.atom, list[i+1].*);
                        var body_expr = Expr{ .list = body };
                        body_expr.replace(&params);
                    },
                    .atom => |atom| {
                        var atom_temp = atom[0..];
                        while (atom_temp[0] == ' ' and atom_temp.len > 0)
                            atom_temp = atom_temp[1..];
                        while (atom_temp[atom_temp.len - 1] == ' ' and atom_temp.len > 0)
                            atom_temp = atom_temp[0..atom_temp.len];
                        if (eql(u8, atom, "print") and list.len >= 2) {
                            var val = Expr{ .list = list[1..] };
                            var effect = Effect{ .print = try val.toString(self.*.allocator) };
                            try effects.append(effect);
                        }
                        if (eql(u8, atom, "define") and list.len >= 3 and eql(u8, @tagName(list[1].*), "atom"))
                            try effects.append(Effect{ .add_def = .{
                                .name = list[1].*.atom,
                                .subst = Expr{ .list = list[2..] },
                            } });
                    },
                }
            },
            else => {},
        }
    }

    fn deinit(self: *Self) void {
        self.*.defs.deinit();
    }
};

pub fn main() anyerror!void {
    const stdin_reader = std.io.getStdIn().reader();
    const stdout_writer = std.io.getStdOut().writer();
    try stdout_writer.writeAll("Lisp REPL\n");
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    var state = State.init(&gpa.allocator());
    defer state.deinit();
    while (true) {
        var arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit();
        var allocator = arena.allocator();
        try stdout_writer.writeAll(">");
        const buffer = (try stdin_reader.readUntilDelimiterOrEofAlloc(allocator, '\n', (1 << 64) - 1)).?;
        defer allocator.free(buffer);
        var expr = try Expr.fromStr(buffer, &allocator);
        for (try state.eval(expr)) |effect| {
            switch (effect) {
                .add_def => |def| {
                    _ = try state.defs.getOrPutValue(def.name, def.subst);
                },
                .print => |val| try stdout_writer.print("{s}\n", .{val}),
            }
        }
    }
}
