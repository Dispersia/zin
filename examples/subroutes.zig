const std = @import("std");
const zin = @import("zin");

fn health() zin.Response {
    return zin.Response.text("ok");
}

fn listCards() !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .cards = &[_][]const u8{ "Ace of Spades", "King of Hearts" },
    });
}

fn getCard(path: zin.Path(struct { id: u32 })) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .id = path.id,
        .name = "Ace of Spades",
    });
}

fn createCard(body: zin.Json(struct { name: []const u8 })) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .id = 1,
        .name = body.name,
    });
}

fn listUsers() !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .users = &[_][]const u8{ "Alice", "Bob" },
    });
}

const CardRouter = zin.Router(&.{
    zin.Route.get("/", listCards),
    zin.Route.get("/:id", getCard),
    zin.Route.post("/", createCard),
}, .{});

const UserRouter = zin.Router(&.{
    zin.Route.get("/", listUsers),
}, .{});

const V1Router = zin.Router(&.{
    zin.Route.mount("/cards", CardRouter),
    zin.Route.mount("/users", UserRouter),
}, .{});

const App = zin.Router(&.{
    zin.Route.get("/health", health),
    zin.Route.mount("/api/v1", V1Router),
}, .{});

pub fn main(init: std.process.Init) !void {
    try zin.serve(App, init.io, 3000);
}
