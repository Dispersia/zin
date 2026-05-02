const std = @import("std");
const zin = @import("zin");

fn index() zin.Response {
    return zin.Response.text("Hello, World!");
}

fn greet(req: zin.Request) zin.Response {
    const name = req.pathParam("name") orelse "stranger";
    _ = name;
    return zin.Response.text("Hello!");
}

const App = zin.Router(&.{
    zin.Route.get("/", index),
    zin.Route.get("/greet/:name", greet),
}, .{});

pub fn main(init: std.process.Init) !void {
    try zin.serve(App, init.io, 3000);
}
