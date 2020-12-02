const std = @import("std");
const fs = std.fs;
const stdout = std.io.getStdOut().writer();

const TreeNode = struct {
    parent: ?*TreeNode,
    children: ?std.SinglyLinkedList(*TreeNode) = null,

    pub fn addChild(self: *TreeNode, child: *TreeNode, allocator: *std.mem.Allocator) !void {
        const Node = std.SinglyLinkedList(*TreeNode).Node;
        var child_node = try allocator.create(Node);
        child_node.data = child;
        var child_list = self.children orelse std.SinglyLinkedList(*TreeNode){};
        self.children = child_list;
        child_list.prepend(child_node);
    }

    pub fn countOrbits(self: *TreeNode, recursion_depth: usize) usize {
        var total_orbits: usize = recursion_depth;
        if (self.children) |child_list| {
            var current_node = &child_list.Node;
            while (current_node) |value| : (current_node = current_node.next) {
                total_orbits += value.data.countOrbits();
            }
        }
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    var nodes_by_name = std.StringHashMap(*TreeNode).init(allocator);
    defer nodes_by_name.deinit();
    var head_nodes = std.StringHashMap(*TreeNode).init(allocator);
    defer head_nodes.deinit();

    var working_dir = fs.cwd();
    var file = (try working_dir.openFile("orbits.txt", .{ .read = true, .write = false })).reader();

    var buffer: [1024]u8 = undefined;
    var file_buffer_start: [16536]u8 = undefined;
    var file_buffer_index: usize = 0;
    while (try file.readUntilDelimiterOrEof(buffer[0..], '\n')) |temp_line| {
        if (file_buffer_index + temp_line.len >= file_buffer_start.len) return error.OutOfMemory;
        std.mem.copy(u8, file_buffer_start[file_buffer_index..], temp_line);
        var line = file_buffer_start[file_buffer_index .. file_buffer_index + temp_line.len];
        file_buffer_index += temp_line.len;
        if (splitString(")", line)) |pieces| {
            try stdout.print("{}, {}\n", .{ pieces[0], pieces[1] });
            var center_planet: *TreeNode = undefined;
            if (nodes_by_name.get(pieces[0])) |center| {
                center_planet = center;
            } else {
                center_planet = try allocator.create(TreeNode);
                try nodes_by_name.put(pieces[0], center_planet);
                try head_nodes.put(pieces[0], center_planet);
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
                satellite_planet = try allocator.create(TreeNode);
                try nodes_by_name.put(pieces[1], satellite_planet);
            }
            try center_planet.addChild(satellite_planet, allocator);
        } else return error.Format;
    }
    try stdout.print("{}\n", .{head_nodes.count()});
}
