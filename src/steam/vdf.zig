const std = @import("std");

pub const NodeType = enum {
    Object,
    String,
};

pub const Node = struct {
    node_type: NodeType,
    key: ?[]const u8, // null for root node
    string_value: ?[]const u8,
    first_child: ?*Node,
    next_sibling: ?*Node,
};

pub fn parse(allocator: std.mem.Allocator, text: []const u8) !*Node {
    var p = Parser{
        .allocator = allocator,
        .input = text,
        .pos = 0,
    };
    return p.parseRoot();
}

/// Free a VDF parse tree and all associated memory
pub fn freeTree(allocator: std.mem.Allocator, node: *Node) void {
    // Free all children recursively
    var child_opt = node.first_child;
    while (child_opt) |child| {
        const next = child.next_sibling;
        freeTree(allocator, child);
        child_opt = next;
    }

    // Free the key string if it exists
    if (node.key) |k| {
        allocator.free(k);
    }

    // Free the string value if it exists
    if (node.string_value) |v| {
        allocator.free(v);
    }

    // Free the node itself
    allocator.destroy(node);
}

const Parser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize,

    fn parseRoot(self: *Parser) !*Node {
        self.skipWhitespace();
        // Root is an object with no key
        var root = try self.allocNode();
        root.node_type = .Object;
        root.key = null;
        root.string_value = null;
        root.first_child = null;
        root.next_sibling = null;

        try self.parseObjectBody(root);
        return root;
    }

    fn parseObjectBody(self: *Parser, parent: *Node) !void {
        var last_child: ?*Node = null;

        while (true) {
            self.skipWhitespace();
            if (self.eof()) break;

            const c = self.peek();
            if (c == '}') {
                _ = self.advance();
                break;
            }

            // Expect a "key"
            const key = try self.parseQuotedString();

            self.skipWhitespace();
            if (self.eof()) break;

            const next_char = self.peek();
            if (next_char == '{') {
                // Object value
                _ = self.advance(); // consume '{'

                var child = try self.allocNode();
                child.node_type = .Object;
                child.key = key;
                child.string_value = null;
                child.first_child = null;
                child.next_sibling = null;

                if (last_child) |lc| lc.next_sibling = child else parent.first_child = child;
                last_child = child;

                try self.parseObjectBody(child);
            } else {
                // String value
                const value = try self.parseQuotedString();

                var child = try self.allocNode();
                child.node_type = .String;
                child.key = key;
                child.string_value = value;
                child.first_child = null;
                child.next_sibling = null;

                if (last_child) |lc| lc.next_sibling = child else parent.first_child = child;
                last_child = child;
            }
        }
    }

    fn parseQuotedString(self: *Parser) ![]u8 {
        self.skipWhitespace();
        if (self.eof() or self.peek() != '"') return error.ExpectedQuote;
        _ = self.advance(); // consume opening quote

        const start = self.pos;
        while (!self.eof() and self.peek() != '"') {
            // Steam VDF is usually ASCII-ish; we'll skip escape handling for now.
            _ = self.advance();
        }

        if (self.eof()) return error.UnterminatedString;
        const end = self.pos;

        _ = self.advance(); // closing quote

        const slice = self.input[start..end];

        // Allocate and copy so lifetime is tied to allocator, not input slice (safer if you reuse input).
        const buffer = try self.allocator.alloc(u8, slice.len);
        std.mem.copyForwards(u8, buffer, slice);
        return buffer;
    }

    fn skipWhitespace(self: *Parser) void {
        while (!self.eof()) {
            const c = self.peek();
            // VDF also has // comments sometimes; we can skip them.
            if (c == '/' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '/') {
                self.pos += 2;
                while (!self.eof() and self.peek() != '\n') {
                    self.pos += 1;
                }
                continue;
            }

            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
                continue;
            }

            break;
        }
    }

    fn eof(self: *Parser) bool {
        return self.pos >= self.input.len;
    }

    fn peek(self: *Parser) u8 {
        return self.input[self.pos];
    }

    fn advance(self: *Parser) u8 {
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    fn allocNode(self: *Parser) !*Node {
        return try self.allocator.create(Node);
    }
};

pub fn getChild(parent: *Node, key: []const u8) !*Node {
    var child_opt = parent.first_child;
    while (child_opt) |child| : (child_opt = child.next_sibling) {
        if (child.key) |k| {
            if (std.mem.eql(u8, k, key)) return child;
        }
    }
    return error.ChildNotFound;
}

pub fn asString(node: *Node) ![]const u8 {
    if (node.node_type != .String) return error.NotAString;
    if (node.string_value) |v| return v;
    return error.NoValue;
}

pub const ChildIterator = struct {
    current: ?*Node,

    pub fn next(it: *ChildIterator) ?*Node {
        if (it.current) |c| {
            const out = c;
            it.current = c.next_sibling;
            return out;
        }
        return null;
    }
};

pub fn childIterator(parent: *Node) ChildIterator {
    return ChildIterator{ .current = parent.first_child };
}
