const std = @import("std");

pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;
pub const Header = @import("response.zig").Header;

const extractors = @import("extractors.zig");
pub const Json = extractors.Json;
pub const Path = extractors.Path;
pub const Query = extractors.Query;

const router_mod = @import("router.zig");
pub const Route = router_mod.Route;
pub const Router = router_mod.Router;
pub const Method = router_mod.Method;
pub const Options = router_mod.Options;

const mw = @import("middleware.zig");
pub const BeforeFn = mw.BeforeFn;
pub const AfterFn = mw.AfterFn;

pub const serve = @import("server.zig").serve;

test {
    _ = @import("routing.zig");
    _ = @import("extractors.zig");
}
