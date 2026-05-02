const std = @import("std");
const http = std.http;
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const max_headers = 16;

pub const Header = struct {
    name: []const u8 = "",
    value: []const u8 = "",
};

pub const Response = struct {
    status: http.Status = .ok,
    body: []const u8 = "",
    content_type: []const u8 = "text/plain",
    headers: [max_headers]Header = @splat(.{}),
    header_count: u8 = 0,

    pub fn text(body: []const u8) Response {
        return .{ .body = body };
    }

    pub fn json(alloc: Allocator, value: anytype) !Response {
        var aw: Io.Writer.Allocating = .init(alloc);
        std.json.Stringify.value(value, .{}, &aw.writer) catch return error.OutOfMemory;
        return .{
            .body = aw.written(),
            .content_type = "application/json",
        };
    }

    pub fn withStatus(s: http.Status) Response {
        return .{ .status = s };
    }

    pub fn textWithStatus(s: http.Status, body: []const u8) Response {
        return .{ .status = s, .body = body };
    }

    pub fn withHeader(self: Response, name: []const u8, value: []const u8) Response {
        var result = self;
        if (result.header_count < max_headers) {
            result.headers[result.header_count] = .{ .name = name, .value = value };
            result.header_count += 1;
        }
        return result;
    }

    pub fn getHeaders(self: *const Response) []const Header {
        return self.headers[0..self.header_count];
    }
};
