const std = @import("std");
const http = std.http;
const routing = @import("routing.zig");
const extractors = @import("extractors.zig");
const mw = @import("middleware.zig");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

pub const Method = http.Method;
pub const Options = mw.Options;

fn RouteDef(comptime HandlerType: type) type {
    return struct {
        method: http.Method,
        path: []const u8,
        handler: HandlerType,
    };
}

fn MountDef(comptime SubRouter: type) type {
    return struct {
        prefix: []const u8,
        pub const __zin_mount = true;
        pub const router = SubRouter;
    };
}

pub const Route = struct {
    pub fn get(comptime path: []const u8, comptime handler: anytype) RouteDef(@TypeOf(handler)) {
        return .{ .method = .GET, .path = path, .handler = handler };
    }
    pub fn post(comptime path: []const u8, comptime handler: anytype) RouteDef(@TypeOf(handler)) {
        return .{ .method = .POST, .path = path, .handler = handler };
    }
    pub fn put(comptime path: []const u8, comptime handler: anytype) RouteDef(@TypeOf(handler)) {
        return .{ .method = .PUT, .path = path, .handler = handler };
    }
    pub fn delete(comptime path: []const u8, comptime handler: anytype) RouteDef(@TypeOf(handler)) {
        return .{ .method = .DELETE, .path = path, .handler = handler };
    }
    pub fn patch(comptime path: []const u8, comptime handler: anytype) RouteDef(@TypeOf(handler)) {
        return .{ .method = .PATCH, .path = path, .handler = handler };
    }

    pub fn mount(comptime prefix_raw: []const u8, comptime SubRouter: type) MountDef(SubRouter) {
        const prefix = comptime blk: {
            var p = prefix_raw;
            while (p.len > 1 and p[p.len - 1] == '/') {
                p = p[0 .. p.len - 1];
            }
            break :blk p;
        };
        return .{ .prefix = prefix };
    }
};

pub fn Router(comptime route_defs: anytype, comptime opts: Options) type {
    const route_info = comptime blk: {
        const fields = @typeInfo(@TypeOf(route_defs.*)).@"struct".fields;
        var routes: [fields.len]CompiledRoute = undefined;
        for (fields, 0..) |field, i| {
            const entry = @field(route_defs.*, field.name);
            const EntryType = @TypeOf(entry);
            if (@hasDecl(EntryType, "__zin_mount")) {
                routes[i] = .{
                    .method = .GET,
                    .segments = @splat(.{ .static = "" }),
                    .param_names = @splat(""),
                };
            } else {
                routes[i] = .{
                    .method = entry.method,
                    .segments = routing.parsePathSegments(entry.path),
                    .param_names = routing.extractParamNames(entry.path),
                };
            }
        }
        break :blk routes;
    };
    _ = &route_info;

    return struct {
        pub fn dispatch(req: Request) Response {
            inline for (opts.before) |before_fn| {
                if (before_fn(req)) |resp| return applyAfter(req, resp);
            }

            const fields = @typeInfo(@TypeOf(route_defs.*)).@"struct".fields;
            inline for (fields, 0..) |field, i| {
                const entry = @field(route_defs.*, field.name);
                const EntryType = @TypeOf(entry);

                if (comptime @hasDecl(EntryType, "__zin_mount")) {
                    if (matchMount(req.path, entry.prefix)) |remaining| {
                        var sub_req = req;
                        sub_req.path = remaining;
                        const sub_resp = EntryType.router.dispatch(sub_req);
                        if (sub_resp.status != .not_found) {
                            return applyAfter(req, sub_resp);
                        }
                    }
                } else {
                    const ri = route_info[i];
                    if (req.method == ri.method) {
                        if (routing.matchPath(&ri.segments, req.path)) |param_values| {
                            const resp = extractors.callHandler(
                                entry.handler,
                                &ri.param_names,
                                &param_values,
                                req,
                            );
                            return applyAfter(req, resp);
                        }
                    }
                }
            }
            return applyAfter(req, Response.textWithStatus(.not_found, "Not Found"));
        }

        fn applyAfter(req: Request, response: Response) Response {
            var resp = response;
            inline for (opts.after) |after_fn| {
                resp = after_fn(req, resp);
            }
            return resp;
        }
    };
}

fn matchMount(path: []const u8, comptime prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const remaining = path[prefix.len..];
    if (remaining.len == 0) return "/";
    if (remaining[0] == '/') return remaining;
    return null;
}

const CompiledRoute = struct {
    method: http.Method,
    segments: [routing.max_segments]routing.Segment,
    param_names: [routing.max_segments][]const u8,
};
