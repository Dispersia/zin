const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

const ExtractorKind = enum { json, path, query };

pub fn Json(comptime T: type) type {
    return makeExtractorType(T, .json);
}

pub fn Path(comptime T: type) type {
    return makeExtractorType(T, .path);
}

pub fn Query(comptime T: type) type {
    return makeExtractorType(T, .query);
}

fn makeExtractorType(comptime Inner: type, comptime kind: ExtractorKind) type {
    const inner_fields = @typeInfo(Inner).@"struct".fields;
    const n = inner_fields.len;
    var names: [n + 1][:0]const u8 = undefined;
    var types: [n + 1]type = undefined;
    var attrs: [n + 1]std.builtin.Type.StructField.Attributes = undefined;
    for (inner_fields, 0..) |f, i| {
        names[i] = f.name;
        types[i] = f.type;
        attrs[i] = .{
            .default_value_ptr = f.default_value_ptr,
            .@"align" = f.alignment,
            .@"comptime" = f.is_comptime,
        };
    }
    const default_kind: ExtractorKind = kind;
    names[n] = "__zin_kind";
    types[n] = ExtractorKind;
    attrs[n] = .{ .default_value_ptr = @ptrCast(&default_kind), .@"comptime" = true };
    return @Struct(.auto, null, &names, &types, &attrs);
}

fn extractorKind(comptime T: type) ?ExtractorKind {
    if (@typeInfo(T) != .@"struct") return null;
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, "__zin_kind")) {
            return comptime f.defaultValue().?;
        }
    }
    return null;
}

fn InnerType(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    var names: [fields.len - 1][:0]const u8 = undefined;
    var types: [fields.len - 1]type = undefined;
    var attrs: [fields.len - 1]std.builtin.Type.StructField.Attributes = undefined;
    var j: usize = 0;
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, "__zin_kind")) continue;
        names[j] = f.name;
        types[j] = f.type;
        attrs[j] = .{
            .default_value_ptr = f.default_value_ptr,
            .@"align" = f.alignment,
            .@"comptime" = f.is_comptime,
        };
        j += 1;
    }
    return @Struct(.auto, null, &names, &types, &attrs);
}

pub fn callHandler(
    comptime handler: anytype,
    comptime param_names: []const []const u8,
    param_values: []const []const u8,
    req: Request,
) Response {
    const H = @TypeOf(handler);
    const params = @typeInfo(H).@"fn".params;
    var args: std.meta.ArgsTuple(H) = undefined;

    inline for (params, 0..) |param, i| {
        const T = param.type.?;
        args[i] = extractArg(T, param_names, param_values, req) catch {
            return Response.textWithStatus(.bad_request, "Bad Request");
        };
    }

    const ReturnType = @typeInfo(H).@"fn".return_type.?;
    if (@typeInfo(ReturnType) == .error_union) {
        return @call(.auto, handler, args) catch
            Response.textWithStatus(.internal_server_error, "Internal Server Error");
    } else {
        return @call(.auto, handler, args);
    }
}

fn extractArg(
    comptime T: type,
    comptime param_names: []const []const u8,
    param_values: []const []const u8,
    req: Request,
) !T {
    if (T == Request) {
        return Request{
            .method = req.method,
            .path = req.path,
            .query_string = req.query_string,
            .body = req.body,
            .allocator = req.allocator,
            .param_names = param_names,
            .param_values = param_values,
        };
    }

    if (T == *const Request) {
        @compileError("Use `Request` (by value) instead of `*const Request` as handler parameter");
    }

    const kind = comptime extractorKind(T) orelse
        @compileError("Unsupported handler parameter type: " ++ @typeName(T));
    return switch (kind) {
        .json => extractJson(T, req.body),
        .path => extractPathParams(T, param_names, param_values),
        .query => extractQuery(T, req.query_string),
    };
}

fn extractPathParams(
    comptime T: type,
    comptime param_names: []const []const u8,
    param_values: []const []const u8,
) !T {
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "__zin_kind")) continue;
        const raw = findParam(param_names, param_values, field.name) orelse return error.BadRequest;
        @field(result, field.name) = parseValue(field.type, raw) orelse return error.BadRequest;
    }
    return result;
}

fn findParam(
    comptime names: []const []const u8,
    values: []const []const u8,
    comptime target: []const u8,
) ?[]const u8 {
    inline for (names, 0..) |name, i| {
        if (comptime std.mem.eql(u8, name, target)) return values[i];
    }
    return null;
}

fn parseValue(comptime T: type, raw: []const u8) ?T {
    if (T == []const u8) return raw;
    if (@typeInfo(T) == .int) return std.fmt.parseInt(T, raw, 10) catch null;
    if (@typeInfo(T) == .float) return std.fmt.parseFloat(T, raw) catch null;
    if (T == bool) {
        if (std.mem.eql(u8, raw, "true")) return true;
        if (std.mem.eql(u8, raw, "false")) return false;
        return null;
    }
    @compileError("Unsupported Path field type: " ++ @typeName(T));
}

fn extractJson(comptime T: type, body: []const u8) !T {
    const Inner = InnerType(T);
    const parsed = std.json.parseFromSlice(Inner, std.heap.page_allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch return error.BadRequest;
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "__zin_kind")) continue;
        @field(result, field.name) = @field(parsed.value, field.name);
    }
    return result;
}

fn extractQuery(comptime T: type, query_string: ?[]const u8) !T {
    const qs = query_string orelse return error.BadRequest;
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "__zin_kind")) continue;
        const raw = findQueryParam(qs, field.name);
        if (raw) |r| {
            @field(result, field.name) = parseValue(field.type, r) orelse return error.BadRequest;
        } else if (field.defaultValue()) |d| {
            @field(result, field.name) = d;
        } else return error.BadRequest;
    }
    return result;
}

pub fn findQueryParam(qs: []const u8, comptime name: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, qs, '&');
    while (iter.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], name)) {
            return pair[eq + 1 ..];
        }
    }
    return null;
}

test "query param parsing" {
    const v = findQueryParam("name=alice&age=30", "age");
    try std.testing.expectEqualStrings("30", v.?);
    try std.testing.expectEqual(null, findQueryParam("name=alice", "missing"));
}
