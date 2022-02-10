pub const std = @import("std");

const assert = std.debug.assert;
const Vector = std.meta.Vector;

pub const ParseError = error{
    Token,
    NewLine,
    Version,
    TooManyHeaders,
    HeaderName,
    HeaderValue,
    Partial,
    Status,
};

/// Cursed code I stole from bun (by Jarred Sumner).
/// Converts cases into an integer and does int comparisons on them
fn ExactSizeMatcher(comptime max_bytes: usize) type {
    switch (max_bytes) {
        1, 2, 4, 8, 12, 16 => {},
        else => {
            @compileError("max_bytes must be 1, 2, 4, 8, 12, or 16.");
        },
    }

    const T = std.meta.Int(
        .unsigned,
        max_bytes * 8,
    );

    return struct {
        pub fn match(str: anytype) T {
            switch (str.len) {
                1...max_bytes - 1 => {
                    var tmp = std.mem.zeroes([max_bytes]u8);
                    std.mem.copy(u8, &tmp, str[0..str.len]);
                    return std.mem.readIntNative(T, &tmp);
                },
                max_bytes => {
                    return std.mem.readIntSliceNative(T, str);
                },
                0 => {
                    return 0;
                },
                else => {
                    return std.math.maxInt(T);
                },
            }
        }

        pub fn case(comptime str: []const u8) T {
            if (str.len < max_bytes) {
                var bytes = std.mem.zeroes([max_bytes]u8);
                const slice_bytes = std.mem.sliceAsBytes(str);
                std.mem.copy(u8, &bytes, slice_bytes);
                return std.mem.readIntNative(T, &bytes);
            } else if (str.len == max_bytes) {
                return std.mem.readIntNative(T, str[0..str.len]);
            } else {
                @compileError("str: \"" ++ str ++ "\" too long");
            }
        }
    };
}

/// ASCII codes to accept URI string
/// i.e. A-Z a-z 0-9 !#$%&'*+-._();:@=,/?[]~^
/// TODO: Make a stricter checking for URI string?
// zig fmt: off
const URI_MAP = [256]u1{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
//  \0                            \n
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
//  commands
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
//  \w !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1,
//  0  1  2  3  4  5  6  7  8  9  :  ;  <  =  >  ?
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
//  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
//  P  Q  R  S  T  U  V  W  X  Y  Z  [  \  ]  ^  _
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
//  `  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
//  p  q  r  s  t  u  v  w  x  y  z  {  |  }  ~  del
    //   ====== Extended ASCII (aka. obs-text) ======
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};
// zig fmt: on

fn isURIToken(b: u8) bool {
    return URI_MAP[b] == 1;
}
fn isToken(b: u8) bool {
    return b > 0x1F and b < 0x7F;
}

const HEADER_NAME_MAP = [256]u1{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

fn isHeaderNameToken(b: u8) bool {
    return HEADER_NAME_MAP[b] == 1;
}

const HEADER_VALUE_MAP = [256]u1{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

const _HEADER_VALUE_V: Vector(256, u1) = HEADER_VALUE_MAP;
const HEADER_VALUE_VECTOR: Vector(256, bool) = _HEADER_VALUE_V == @splat(256, @intCast(u1, 1));

fn isHeaderValueToken(b: u8) bool {
    return HEADER_VALUE_MAP[b] == 1;
}

// fn isHeaderValueTokenVectorized(b: anytype) Vector(@typeInfo(@TypeOf(b)).Vector.len, bool) {
//     return HEADER_VALUE_VECTOR[b];
// }

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    minor_version: usize,
    code: u16,
    headers: []const Header,
    reason: []const u8,
    bytes_read: usize = 0,

    pub fn parse(buf: []const u8, headers: []Header) ParseError!Response {
        var parser = Parser.init(buf);
        // try parser.skipEmptyLines();

        var minor_version = try parser.parseVersion();
        var code = try parser.parseCode();

        var reason = "";

        // RFC7230 says there must be 'SP' and then reason-phrase, but admits
        // its only for legacy reasons. With the reason-phrase completely
        // optional (and preferred to be omitted) in HTTP2, we'll just
        // handle any response that doesn't include a reason-phrase, because
        // it's more lenient, and we don't care anyways.
        //
        // So, a SP means parse a reason-phrase.
        // A newline means go to headers.
        // Anything else we'll say is a malformed status.
        switch (parser.next() orelse return error.Partial) {
            ' ' => {
                reason = try parser.parseReason();
            },
            '\r' => {
                parser.pos += 1;
                if (!parser.expect('\n')) return error.Status;
            },
            '\n' => {},
            else => return error.Status,
        }

        const headers_len = try parser.parseHeaders(headers);

        return Response{
            .minor_version = minor_version,
            .code = code,
            .headers = headers[0 .. headers_len - 1],
            .reason = reason,
            .bytes_read = parser.pos,
        };
    }
};

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: []const Header,
    minor_version: usize,

    pub fn parse(buf: []const u8, headers: []Header) ParseError!Request {
        var parser = Parser.init(buf);
        // try parser.skipEmptyLines();

        var method = try parser.parseToken();
        var path = try parser.parseURI();
        var minor_version = try parser.parseVersion();
        parser.parseNewline() catch |err| {
            if (parser.pos >= parser.buf.len) {
                return Request{
                    .method = method,
                    .minor_version = minor_version,
                    .path = path,
                    .headers = headers,
                };
            } else return err;
        };

        _ = try parser.parseHeaders(headers);

        return Request{
            .method = method,
            .minor_version = minor_version,
            .path = path,
            .headers = headers,
        };
    }
};

test "parse request" {
    const REQ = "GET /hello HTTP/1.1\r\n" ++
        "User-Agent:1234\r\n\r\n";

    var headers: [32]Header = undefined;

    var req = try Request.parse(REQ, &headers);

    try std.testing.expectEqualStrings("GET", req.method);
    try std.testing.expectEqualStrings("/hello", req.path);
    try std.testing.expectEqual(@intCast(usize, 1), req.minor_version);

    try std.testing.expectEqualStrings("User-Agent", headers[0].name);
    try std.testing.expectEqualStrings("1234\r\n", headers[0].value);
}

const Parser = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn init(buf: []const u8) Parser {
        return .{ .buf = buf };
    }

    inline fn expect(self: *Parser, ch: u8) bool {
        if (self.buf[self.pos] == ch) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    inline fn expectNext(self: *Parser, ch: u8) bool {
        var b = self.peek() orelse return false;
        if (b == ch) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    inline fn next(self: *Parser) ?u8 {
        if (self.buf.len > self.pos) {
            self.pos += 1;
            return self.buf[self.pos];
        }
        return null;
    }

    inline fn peek(self: *Parser) ?u8 {
        if (self.buf.len > self.pos) {
            return self.buf[self.pos];
        }
        return null;
    }

    const Version = ExactSizeMatcher(8);

    /// Parse a version, like `HTTP/1.1`
    /// Returns the minor version, and errors if the major version isn't 1
    pub fn parseVersion(self: *Parser) ParseError!usize {
        if (self.buf.len < self.pos + 8) return error.Version;
        switch (Version.match(self.buf[self.pos .. self.pos + 8])) {
            Version.case("HTTP/1.1") => {
                self.pos += 8;
                return 1;
            },
            Version.case("HTTP/1.0") => {
                self.pos += 8;
                return 0;
            },
            else => {
                // std.log.warn("{s}", .{self.buf[self.pos..]});
                return error.Version;
            },
        }
    }

    pub fn parseURI(self: *Parser) ParseError![]const u8 {
        var start = self.pos;
        while (true) {
            var ch = self.next() orelse return error.Partial;
            if (ch == ' ') {
                self.pos += 1;
                return self.buf[start .. self.pos - 1];
            } else if (!isURIToken(ch)) {
                return error.Token;
            }
        }
    }

    pub fn parseToken(self: *Parser) ParseError![]const u8 {
        var start = self.pos;
        while (true) {
            var ch = self.next() orelse return error.Partial;
            if (ch == ' ') {
                self.pos += 1;
                return self.buf[start .. self.pos - 1];
            } else if (!isToken(ch)) {
                return error.Token;
            }
        }
    }

    /// From [RFC 7230](https://tools.ietf.org/html/rfc7230):
    ///
    /// > ```notrust
    /// > reason-phrase  = *( HTAB / SP / VCHAR / obs-text )
    /// > HTAB           = %x09        ; horizontal tab
    /// > VCHAR          = %x21-7E     ; visible (printing) characters
    /// > obs-text       = %x80-FF
    /// > ```
    ///
    /// > A.2.  Changes from RFC 2616
    /// >
    /// > Non-US-ASCII content in header fields and the reason phrase > has been obsoleted and made opaque (the TEXT rule was removed).
    pub fn parseReason(self: *Parser) ParseError![]const u8 {
        var start = self.pos;
        var seen_obs_text = false;
        while (true) {
            var ch = self.next() orelse return error.Partial;
            if (ch == '\r') {
                self.pos += 1;
                if (!self.expect('\n')) return error.Status;

                self.pos += 2;
                if (seen_obs_text) {
                    // all bytes up till `i` must have been HTAB / SP / VCHAR
                    return self.buf[start .. self.pos - 2];
                } else {
                    // obs-text characters were found, so return the fallback empty string
                    return "";
                }
            } else if (ch == '\n') {
                self.pos += 1;
                if (seen_obs_text) {
                    // all bytes up till `i` must have been HTAB / SP / VCHAR
                    return self.buf[start .. self.pos - 1];
                } else {
                    // obs-text characters were found, so return the fallback empty string
                    return "";
                }
            } else if (!(ch == 0x09 or ch == ' ' or (ch >= 0x21 and ch <= 0x7E) or ch >= 0x0)) {
                return error.Status;
            } else if (ch >= 0x80) {
                seen_obs_text = true;
            }
        }
    }

    pub fn parseCode(self: *Parser) ParseError!u16 {
        var hundreds = blk: {
            var n = self.next() orelse return error.Partial;
            if (std.ascii.isDigit(n)) return error.Status;
            break :blk n;
        };
        var tens = blk: {
            var n = self.next() orelse return error.Partial;
            if (std.ascii.isDigit(n)) return error.Status;
            break :blk n;
        };
        var ones = blk: {
            var n = self.next() orelse return error.Partial;
            if (std.ascii.isDigit(n)) return error.Status;
            break :blk n;
        };

        return @intCast(u16, hundreds - '0' * 100) + @intCast(u16, tens - '0' * 10) + @intCast(u16, ones - '0');
    }

    /// Returns the number of headers
    pub fn parseHeaders(self: *Parser, headers: []Header) ParseError!usize {
        var header_index: usize = 0;
        while (true) : (header_index += 1) {
            var ch = self.next() orelse break;
            if (ch == '\r') {
                self.pos += 1;
                if (self.expect('\n')) {
                    break;
                }
                return error.NewLine;
            } else if (ch == '\n') {
                self.pos += 1;
                break;
            } else if (!isHeaderNameToken(ch)) {
                return error.HeaderName;
            }

            if (header_index + 1 == headers.len) {
                return error.TooManyHeaders;
            }

            var header: Header = undefined;

            header.name = try self.parseHeaderName();
            header.value = try self.parseHeaderValue();

            // TODO: Trim whitespace off of the value

            headers[header_index] = header;
        }
        return header_index + 1;
    }

    inline fn parseHeaderName(self: *Parser) ParseError![]const u8 {
        var start = self.pos;
        while (true) {
            var ch = self.next() orelse return error.Partial;

            if (ch == ':') {
                self.pos += 1;
                return self.buf[start .. self.pos - 1];
            } else if (!isHeaderNameToken(ch)) {
                self.pos += 1;
                var name = self.buf[start .. self.pos - 1];

                // eat white space between name and colon
                while (true) {
                    var b = self.next() orelse return error.Partial;
                    if (b == ' ' or b == '\t') {
                        continue;
                    } else if (b == ':') {
                        return name;
                    }
                    return error.HeaderName;
                }
            }
        }
    }

    inline fn parseHeaderValue(self: *Parser) ParseError![]const u8 {
        var ch: u8 = undefined;
        var start = self.pos;
        while (true) {
            whitespace_after_colon: while (true) {
                var _start = self.pos;
                ch = self.next() orelse return error.Partial;
                if (ch == ' ' or ch == '\t') {
                    continue :whitespace_after_colon;
                } else {
                    if (!isHeaderValueToken(ch)) {
                        if (ch == '\r') {
                            self.pos += 1;
                            if (!self.expect('\n')) return error.HeaderValue;
                        } else if (ch != '\n') {
                            return error.HeaderValue;
                        }

                        return self.buf[_start.._start];
                    }
                    break :whitespace_after_colon;
                }
            }

            while (true) {
                // parse value till EOL
                value_line: while (true) {
                    // if (self.buf.len >= self.pos + 8) {
                    //     var vec: Vector(8, u8) = self.buf[self.pos..][0..8].*;
                    //     if (!@reduce(.And, isHeaderValueTokenVectorized(vec))) {
                    //         break :value_line;
                    //     }
                    //     self.pos += 8;
                    //     continue :value_line;
                    // }

                    ch = self.next() orelse return error.Partial;
                    if (!isHeaderValueToken(ch)) {
                        break :value_line;
                    }
                }
                // found_ctl
                var skip: usize = s: {
                    if (ch == '\r') {
                        self.pos += 1;
                        if (self.expect('\n')) {
                            break :s 2;
                        }
                        return error.HeaderValue;
                    } else if (ch == '\n') {
                        break :s 1;
                    }
                    return error.HeaderValue;
                };

                self.pos += skip;
                return self.buf[start .. self.pos - skip];
            }
        }
    }

    pub fn parseNewline(self: *Parser) ParseError!void {
        var ch = self.next() orelse return error.Partial;
        switch (ch) {
            '\r' => {
                self.pos += 1;
                if (!self.expect('\n')) return error.NewLine;
            },
            '\n' => {},
            else => return error.NewLine,
        }
    }

    pub fn skipEmptyLines(self: *Parser) ParseError!void {
        while (true) {
            var ch = self.peek() orelse return error.Partial;

            switch (ch) {
                '\r' => {
                    self.pos += 1;
                    if (!self.expectNext('\n')) return error.NewLine;
                },
                '\n' => {
                    self.pos += 1;
                },
                else => break,
            }
        }
    }
};

// pub export fn fhp_parseRequest(
//     buffer: [*c]u8,
//     buffer_len: usize,
//     method: [*c][*c]u8,
//     method_len: [*c]usize,
//     path: [*c][*c]u8,
//     path_len: [*c]usize,
//     minor_version: [*c]usize,
//     headers: [*c]fhp_Header,
//     num_headers: usize,
// ) c_int {
//     var buf =
// }
