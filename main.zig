const std = @import("std");
const fs = std.fs;
const stdout = std.io.getStdOut().writer();

const TreeNode = struct {
    const Node = std.SinglyLinkedList(*TreeNode).Node;
    parent: ?*TreeNode = null,
    children: ?*Node = null,
    name: []u8,

    pub fn addChild(self: *TreeNode, child: *TreeNode, allocator: *std.mem.Allocator) !void {
        var child_node = try allocator.create(Node);
        child_node.data = child;
        child.parent = self;
        if (self.children) |sub_planets| {
            sub_planets.insertAfter(child_node);
        } else {
            child_node.next = null;
            self.children = child_node;
        }
    }

    pub fn countOrbits(self: *TreeNode, recursion_depth: usize) usize {
        var total_orbits: usize = recursion_depth;
        var current_node = self.children;
        while (current_node) |value| : (current_node = value.next) {
            total_orbits += value.data.countOrbits(recursion_depth + 1);
        }
        return total_orbits;
    }

    pub fn findPathTo(self: *TreeNode, exclude_node: *TreeNode, other_name: []u8, hops_count: usize) ?usize {
        if (std.mem.eql(u8, self.name, other_name)) {
            return hops_count;
        }
        // search children first
        var current_node = self.children;
        while (current_node) |value| : (current_node = value.next) {
            if (value.data == exclude_node) continue;
            if (value.data.findPathTo(self, other_name, hops_count + 1)) |count| {
                return count;
            }
        }
        if (self.parent) |parent| {
            if (parent == exclude_node) return null;
            if (parent.findPathTo(self, other_name, hops_count + 1)) |count| {
                return count;
            }
        }
        return null;
    }

    pub fn freeSelf(self: *TreeNode, allocator: *std.mem.Allocator) void {
        var current_node = self.children;
        while (current_node) |value| {
            current_node = value.next;
            allocator.destroy(value);
        }
        allocator.free(self.name);
        allocator.destroy(self);
    }

    pub fn freeSelfAndChildren(self: *TreeNode, allocator: *std.mem.Allocator) void {
        var current_node = self.children;
        while (current_node) |value| {
            value.data.freeSelfAndChildren(allocator);
            current_node = value.next;
            allocator.destroy(value);
        }
        allocator.free(self.name);
        allocator.destroy(self);
    }
};

// split a string at the first occurance of a delim
pub fn splitString(delim: []const u8, string: []u8) ?[2][]u8 {
    var i: usize = 0;
    while (i < string.len - delim.len) : (i += 1) {
        if (std.mem.eql(u8, delim, string[i .. i + delim.len])) {
            return [2][]u8{ string[0..i], string[i + delim.len ..] };
        }
    }
    return null;
}

test "split" {
    var str = "hello, world";
    var str_mut: [str.len]u8 = undefined;
    std.mem.copy(u8, str_mut[0..], str[0..]);
    var split = splitString(", ", str_mut[0..]) orelse unreachable;
    std.testing.expect(std.mem.eql(u8, split[0], "hello"));
    std.testing.expect(std.mem.eql(u8, split[1], "world"));
}

test "hop" {
    var nodes_by_name = std.StringHashMap(*TreeNode).init(std.testing.allocator);
    defer nodes_by_name.deinit();
    defer {
        var iterator = nodes_by_name.iterator();
        while (iterator.next()) |kv| {
            kv.value.freeSelf(std.testing.allocator);
        }
    }
    var root = try buildTree("test.txt", &nodes_by_name, std.testing.allocator);
    var you_node = nodes_by_name.get("YOU") orelse return error.NodeNotFound;
    var you_node_parent = you_node.parent orelse return error.YouNoParent;
    var san_node = nodes_by_name.get("SAN") orelse return error.NodeNotFound;
    var san_node_parent = san_node.parent orelse return error.SanNoParent;
    std.testing.expect(you_node_parent.findPathTo(you_node, san_node_parent.name, 0).? == 4);
}

pub fn buildTree(path: []const u8, nodes_by_name: *std.StringHashMap(*TreeNode), allocator: *std.mem.Allocator) anyerror!*TreeNode {
    var working_dir = fs.cwd();
    var file = (try working_dir.openFile(path, .{ .read = true, .write = false })).reader();

    var buffer: [1024]u8 = undefined;

    var head_nodes = std.StringHashMap(*TreeNode).init(allocator);
    defer head_nodes.deinit();

    while (try file.readUntilDelimiterOrEof(buffer[0..], '\n')) |line| {
        if (splitString(")", line)) |pieces| {
            var center_planet: *TreeNode = undefined;
            if (nodes_by_name.get(pieces[0])) |center| {
                center_planet = center;
            } else {
                var center_name = try allocator.alloc(u8, pieces[0].len);
                errdefer |_| allocator.free(center_name);
                std.mem.copy(u8, center_name, pieces[0]);
                center_planet = try allocator.create(TreeNode);
                center_planet.* = .{ .name = center_name };
                try nodes_by_name.put(center_name, center_planet);
                try head_nodes.put(center_name, center_planet);
            }
            var satellite_planet: *TreeNode = undefined;
            if (nodes_by_name.get(pieces[1])) |satellite| {
                if (head_nodes.remove(pieces[1])) |_| {
                    satellite_planet = satellite;
                } else {
                    // a planet cannot be a satellite to more than one planet
                    return error.DoubleSatellite;
                }
            } else {
                var satellite_name = try allocator.alloc(u8, pieces[1].len);
                errdefer |_| allocator.free(satellite_name);
                std.mem.copy(u8, satellite_name, pieces[1]);
                satellite_planet = try allocator.create(TreeNode);
                satellite_planet.* = .{ .name = satellite_name };
                try nodes_by_name.put(satellite_name, satellite_planet);
            }
            try center_planet.addChild(satellite_planet, allocator);
        } else return error.Format;
    }
    if (head_nodes.count() != 1) return error.NotOneCOM;
    return head_nodes.iterator().next().?.value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    var nodes_by_name = std.StringHashMap(*TreeNode).init(allocator);
    defer nodes_by_name.deinit();
    defer {
        var iterator = nodes_by_name.iterator();
        while (iterator.next()) |kv| {
            kv.value.freeSelf(std.testing.allocator);
        }
    }

    var head = try buildTree("orbits.txt", &nodes_by_name, allocator);

    try stdout.print("{}\n", .{head.countOrbits(0)});

    var you_node = nodes_by_name.get("YOU") orelse return error.YouNotFound;
    var you_node_parent = you_node.parent orelse return error.YouNoParent;
    var san_node = nodes_by_name.get("SAN") orelse return error.SanNotFound;
    var san_node_parent = san_node.parent orelse return error.SanNoParent;
    try stdout.print("{}\n", .{you_node_parent.findPathTo(you_node, san_node_parent.name, 0)});
}
