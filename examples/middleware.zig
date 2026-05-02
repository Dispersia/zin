const std = @import("std");
const zin = @import("zin");

fn logRequest(req: zin.Request) ?zin.Response {
    std.debug.print("{s} {s}\n", .{ @tagName(req.method), req.path });
    return null;
}

fn addServerHeader(_: zin.Request, resp: zin.Response) zin.Response {
    return resp.withHeader("x-powered-by", "Zin");
}

fn index() zin.Response {
    return zin.Response.text("Hello from Zin with middleware!");
}

fn listSecrets() !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .secrets = &[_][]const u8{ "area51", "roswell" },
    });
}

fn getSecret(path: zin.Path(struct { id: u32 })) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, .{
        .id = path.id,
        .value = "classified",
    });
}

const SecretRouter = zin.Router(&.{
    zin.Route.get("/", listSecrets),
    zin.Route.get("/:id", getSecret),
}, .{});

const App = zin.Router(&.{
    zin.Route.get("/", index),
    zin.Route.mount("/secrets", SecretRouter),
}, .{
    .before = &.{logRequest},
    .after = &.{addServerHeader},
});

pub fn main(init: std.process.Init) !void {
    try zin.serve(App, init.io, 3000);
}
