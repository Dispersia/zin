const std = @import("std");
const zin = @import("zin");

const CreateUser = struct {
    name: []const u8,
    email: []const u8,
};

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

fn hello() zin.Response {
    return zin.Response.text("Hello from Zin!");
}

fn getUser(path: zin.Path(struct { id: u32 })) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .id = path.id,
        .message = "User found",
    });
}

fn createUser(body: zin.Json(CreateUser)) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, User{
        .id = 1,
        .name = body.name,
        .email = body.email,
    });
}

fn searchUsers(q: zin.Query(struct { name: []const u8 })) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .query = q.name,
        .results = &[_][]const u8{},
    });
}

const App = zin.Router(&.{
    zin.Route.get("/", hello),
    zin.Route.get("/users/:id", getUser),
    zin.Route.post("/users", createUser),
    zin.Route.get("/search", searchUsers),
}, .{});

pub fn main(init: std.process.Init) !void {
    try zin.serve(App, init.io, 8080);
}
