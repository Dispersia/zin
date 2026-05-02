const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

pub const BeforeFn = *const fn (Request) ?Response;
pub const AfterFn = *const fn (Request, Response) Response;

pub const Options = struct {
    before: []const BeforeFn = &.{},
    after: []const AfterFn = &.{},
};
