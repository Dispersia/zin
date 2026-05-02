const std = @import("std");
const Io = std.Io;
const http = std.http;
const Request = @import("request.zig").Request;
const response_mod = @import("response.zig");
const Response = response_mod.Response;

pub fn serve(comptime RouterType: type, io: Io, port: u16) !void {
    const address: Io.net.IpAddress = .{ .ip4 = .unspecified(port) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    std.debug.print("Zin listening on port {d}\n", .{port});

    const Handler = ConnectionHandler(RouterType);
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| {
                std.debug.print("Accept error: {t}\n", .{e});
                continue;
            },
        };

        group.concurrent(io, Handler.handle, .{ io, stream }) catch |err| {
            std.debug.print("Concurrency error: {t}\n", .{err});
            var copy = stream;
            copy.close(io);
            continue;
        };
    }
}

fn ConnectionHandler(comptime RouterType: type) type {
    return struct {
        fn handle(io: Io, stream: Io.net.Stream) void {
            defer {
                var copy = stream;
                copy.close(io);
            }

            var read_buf: [8192]u8 = undefined;
            var stream_reader = stream.reader(io, &read_buf);
            var write_buf: [8192]u8 = undefined;
            var stream_writer = stream.writer(io, &write_buf);

            var http_server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

            while (true) {
                var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
                defer arena.deinit();

                var http_req = http_server.receiveHead() catch |err| {
                    if (err == error.EndOfStream or err == error.HttpConnectionClosing) return;
                    std.debug.print("Receive error: {t}\n", .{err});
                    return;
                };

                const target = http_req.head.target;
                const keep_alive = http_req.head.keep_alive;

                var body_buf: [65536]u8 = undefined;
                const body_reader = http_req.readerExpectNone(&body_buf);
                var body_aw: Io.Writer.Allocating = .init(arena.allocator());
                _ = body_reader.streamRemaining(&body_aw.writer) catch 0;

                const qmark = std.mem.indexOfScalar(u8, target, '?');
                const path = if (qmark) |q| target[0..q] else target;
                const query_string: ?[]const u8 = if (qmark) |q| target[q + 1 ..] else null;

                const request = Request{
                    .method = http_req.head.method,
                    .path = path,
                    .query_string = query_string,
                    .body = body_aw.written(),
                    .allocator = arena.allocator(),
                    .param_names = &.{},
                    .param_values = &.{},
                };

                const response = RouterType.dispatch(request);

                var hdrs_buf: [response_mod.max_headers + 1]http.Header = undefined;
                hdrs_buf[0] = .{ .name = "content-type", .value = response.content_type };
                const extra = response.getHeaders();
                for (extra, 0..) |h, hi| {
                    hdrs_buf[hi + 1] = .{ .name = h.name, .value = h.value };
                }

                http_req.respond(response.body, .{
                    .status = response.status,
                    .extra_headers = hdrs_buf[0 .. extra.len + 1],
                }) catch return;

                if (!keep_alive) return;
            }
        }
    };
}
