const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;

pub const Request = struct {
    method: http.Method,
    path: []const u8,
    query_string: ?[]const u8,
    body: []const u8,
    allocator: Allocator,
    param_names: []const []const u8,
    param_values: []const []const u8,

    pub fn pathParam(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.param_names, self.param_values) |n, v| {
            if (std.mem.eql(u8, n, name)) return v;
        }
        return null;
    }
};
