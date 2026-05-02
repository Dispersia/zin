const std = @import("std");
const zin = @import("zin");

const Todo = struct {
    id: u32,
    title: []const u8,
    completed: bool,
};

const CreateTodo = struct {
    title: []const u8,
};

const UpdateTodo = struct {
    title: []const u8,
    completed: bool,
};

fn listTodos() !zin.Response {
    return zin.Response.json(std.heap.page_allocator, [_]Todo{
        .{ .id = 1, .title = "Learn Zig", .completed = true },
        .{ .id = 2, .title = "Build a web framework", .completed = false },
        .{ .id = 3, .title = "Deploy to production", .completed = false },
    });
}

const TodoPath = struct { id: u32 };

fn getTodo(path: zin.Path(TodoPath)) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, Todo{
        .id = path.id,
        .title = "Example todo",
        .completed = false,
    });
}

fn createTodo(body: zin.Json(CreateTodo)) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, Todo{
        .id = 42,
        .title = body.title,
        .completed = false,
    });
}

fn updateTodo(path: zin.Path(TodoPath), body: zin.Json(UpdateTodo)) !zin.Response {
    return zin.Response.json(std.heap.page_allocator, Todo{
        .id = path.id,
        .title = body.title,
        .completed = body.completed,
    });
}

fn deleteTodo() zin.Response {
    return zin.Response.withStatus(.no_content);
}

const App = zin.Router(&.{
    zin.Route.get("/todos", listTodos),
    zin.Route.get("/todos/:id", getTodo),
    zin.Route.post("/todos", createTodo),
    zin.Route.put("/todos/:id", updateTodo),
    zin.Route.delete("/todos/:id", deleteTodo),
}, .{});

pub fn main(init: std.process.Init) !void {
    try zin.serve(App, init.io, 3000);
}
