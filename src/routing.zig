const std = @import("std");

pub const max_segments = 16;

pub const Segment = union(enum) {
    static: []const u8,
    param: []const u8,
};

pub fn parsePathSegments(comptime path: []const u8) [max_segments]Segment {
    var segments: [max_segments]Segment = @splat(.{ .static = "" });
    var iter = std.mem.splitScalar(u8, path, '/');
    var i: usize = 0;
    while (iter.next()) |seg| {
        if (seg.len == 0) continue;
        if (seg[0] == ':') {
            segments[i] = .{ .param = seg[1..] };
        } else {
            segments[i] = .{ .static = seg };
        }
        i += 1;
    }
    return segments;
}

pub fn extractParamNames(comptime path: []const u8) [max_segments][]const u8 {
    var names: [max_segments][]const u8 = @splat("");
    var iter = std.mem.splitScalar(u8, path, '/');
    var i: usize = 0;
    while (iter.next()) |seg| {
        if (seg.len == 0) continue;
        if (seg[0] == ':') {
            names[i] = seg[1..];
        }
        i += 1;
    }
    return names;
}

pub fn matchPath(
    comptime segments: *const [max_segments]Segment,
    path: []const u8,
) ?[max_segments][]const u8 {
    var param_values: [max_segments][]const u8 = @splat("");
    var path_iter = std.mem.splitScalar(u8, path, '/');
    inline for (segments, 0..) |seg, i| {
        switch (seg) {
            .static => |s| {
                if (s.len == 0) {
                    var remaining = false;
                    while (path_iter.next()) |rem| {
                        if (rem.len > 0) {
                            remaining = true;
                            break;
                        }
                    }
                    return if (remaining) null else param_values;
                }
                const actual = path_iter.next() orelse return null;
                if (actual.len == 0) {
                    const actual2 = path_iter.next() orelse return null;
                    if (!std.mem.eql(u8, actual2, s)) return null;
                } else {
                    if (!std.mem.eql(u8, actual, s)) return null;
                }
            },
            .param => {
                var actual = path_iter.next() orelse return null;
                if (actual.len == 0) {
                    actual = path_iter.next() orelse return null;
                }
                param_values[i] = actual;
            },
        }
    }
    return param_values;
}

test "path parsing" {
    const segments = comptime parsePathSegments("/users/:id/posts");
    try std.testing.expectEqualStrings("users", segments[0].static);
    try std.testing.expectEqualStrings("id", segments[1].param);
    try std.testing.expectEqualStrings("posts", segments[2].static);
}

test "path matching" {
    const segments = comptime parsePathSegments("/users/:id");
    if (matchPath(&segments, "/users/42")) |values| {
        try std.testing.expectEqualStrings("42", values[1]);
    } else {
        return error.TestFailed;
    }
    try std.testing.expectEqual(null, matchPath(&segments, "/posts/42"));
}
