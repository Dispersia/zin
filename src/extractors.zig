const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

const ExtractorKind = enum { json, path, query };

const StructInfo = std.lang.Type.Struct;
const FieldAttributes = StructInfo.FieldAttributes;

pub fn Json(comptime T: type) type {
    return makeExtractorType(T, .json);
}

pub fn Path(comptime T: type) type {
    return makeExtractorType(T, .path);
}

pub fn Query(comptime T: type) type {
    return makeExtractorType(T, .query);
}

const kind_field = "__zin_kind";

fn makeExtractorType(comptime Inner: type, comptime kind: ExtractorKind) type {
    const info = @typeInfo(Inner).@"struct";
    const n = info.field_names.len;
    var names: [n + 1][:0]const u8 = undefined;
    var types: [n + 1]type = undefined;
    var attrs: [n + 1]FieldAttributes = undefined;
    for (0..n) |i| {
        names[i] = info.field_names[i];
        types[i] = info.field_types[i];
        attrs[i] = info.field_attrs[i];
    }
    const default_kind: ExtractorKind = kind;
    names[n] = kind_field;
    types[n] = ExtractorKind;
    attrs[n] = .{ .default_value_ptr = @ptrCast(&default_kind), .@"comptime" = true };
    return @Struct(.auto, null, &names, &types, &attrs);
}

fn isKindField(comptime name: []const u8) bool {
    return std.mem.eql(u8, name, kind_field);
}

fn extractorKind(comptime T: type) ?ExtractorKind {
    if (@typeInfo(T) != .@"struct") return null;
    const info = @typeInfo(T).@"struct";
    inline for (info.field_names, info.field_attrs) |name, attrs| {
        if (comptime isKindField(name)) {
            return comptime attrs.defaultValue(ExtractorKind).?;
        }
    }
    return null;
}

fn InnerType(comptime T: type) type {
    const info = @typeInfo(T).@"struct";
    const n = info.field_names.len - 1;
    var names: [n][:0]const u8 = undefined;
    var types: [n]type = undefined;
    var attrs: [n]FieldAttributes = undefined;
    var j: usize = 0;
    for (info.field_names, info.field_types, info.field_attrs) |name, FieldType, field_attrs| {
        if (isKindField(name)) continue;
        names[j] = name;
        types[j] = FieldType;
        attrs[j] = field_attrs;
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
    const fn_info = @typeInfo(H).@"fn";
    var args: std.meta.ArgsTuple(H) = undefined;

    inline for (fn_info.param_types, 0..) |param_type, i| {
        const T = param_type.?;
        args[i] = extractArg(T, param_names, param_values, req) catch {
            return Response.textWithStatus(.bad_request, "Bad Request");
        };
    }

    const ReturnType = fn_info.return_type.?;
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
    const info = @typeInfo(T).@"struct";
    var result: T = undefined;
    inline for (info.field_names, info.field_types) |name, FieldType| {
        if (comptime isKindField(name)) continue;
        const raw = findParam(param_names, param_values, name) orelse return error.BadRequest;
        @field(result, name) = parseValue(FieldType, raw) orelse return error.BadRequest;
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
    const info = @typeInfo(T).@"struct";
    var result: T = undefined;
    inline for (info.field_names) |name| {
        if (comptime isKindField(name)) continue;
        @field(result, name) = @field(parsed.value, name);
    }
    return result;
}

fn extractQuery(comptime T: type, query_string: ?[]const u8) !T {
    const qs = query_string orelse return error.BadRequest;
    const info = @typeInfo(T).@"struct";
    var result: T = undefined;
    inline for (info.field_names, info.field_types, info.field_attrs) |name, FieldType, attrs| {
        if (comptime isKindField(name)) continue;
        const raw = findQueryParam(qs, name);
        if (raw) |r| {
            @field(result, name) = parseValue(FieldType, r) orelse return error.BadRequest;
        } else if (comptime attrs.defaultValue(FieldType)) |d| {
            @field(result, name) = d;
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

test "extractor kinds" {
    const P = Path(struct { id: u32 });
    try std.testing.expectEqual(ExtractorKind.path, extractorKind(P).?);
    const J = Json(struct { name: []const u8 });
    try std.testing.expectEqual(ExtractorKind.json, extractorKind(J).?);
    try std.testing.expectEqual(null, extractorKind(struct { x: u8 }));
}

test "path param extraction" {
    const P = Path(struct { id: u32, slug: []const u8 });
    const names = [_][]const u8{ "id", "slug" };
    const values = [_][]const u8{ "42", "hello" };
    const p = try extractPathParams(P, &names, &values);
    try std.testing.expectEqual(@as(u32, 42), p.id);
    try std.testing.expectEqualStrings("hello", p.slug);
}

test "query extraction with defaults" {
    const Q = Query(struct { name: []const u8, limit: u32 = 10 });
    const q = try extractQuery(Q, "name=alice");
    try std.testing.expectEqualStrings("alice", q.name);
    try std.testing.expectEqual(@as(u32, 10), q.limit);
    try std.testing.expectError(error.BadRequest, extractQuery(Q, "limit=5"));
}

test "json extraction" {
    const J = Json(struct { title: []const u8, done: bool });
    const j = try extractJson(J, "{\"title\":\"x\",\"done\":true,\"extra\":1}");
    try std.testing.expectEqualStrings("x", j.title);
    try std.testing.expect(j.done);
}
