const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const ArrayList = std.ArrayList;

const default_alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

///encode encodes a list of numbers into a sqids ID.
pub fn encode(allocator: mem.Allocator, numbers: []const u64, alphabet: []const u8) ![]const u8 {
    if (numbers.len == 0) {
        return "";
    }

    const increment: u64 = 0;

    const encoding_alphabet = try allocator.alloc(u8, alphabet.len);
    defer allocator.free(encoding_alphabet);
    @memcpy(encoding_alphabet, alphabet);
    shuffle(encoding_alphabet);

    return try encodeNumbers(allocator, numbers, encoding_alphabet, increment);
}

fn encodeNumbers(allocator: mem.Allocator, numbers: []const u64, alphabet: []u8, increment: u64) ![]const u8 {
    if (increment > alphabet.len) {
        return error.ReachedMaxAttempts;
    }

    // Get semi-random offset.
    var offset: u64 = numbers.len;

    for (numbers, 0..) |n, i| {
        offset += i;
        offset += alphabet[n % alphabet.len];
    }

    offset %= alphabet.len;
    offset = (offset + increment) % alphabet.len;

    mem.rotate(u8, alphabet, offset);

    const prefix = alphabet[0];

    mem.reverse(u8, alphabet);

    var ret = ArrayList(u8).init(allocator);
    defer ret.deinit();

    try ret.append(prefix);

    for (numbers, 0..) |n, i| {
        const alphabetWithoutSeparator = alphabet[1..];
        const x = try toID(allocator, n, alphabetWithoutSeparator);
        defer allocator.free(x);
        try ret.appendSlice(x);

        // If it's not the last number:
        if (i < numbers.len - 1) {
            try ret.append(alphabet[0]);
            shuffle(alphabet);
        }
    }

    const id = try ret.toOwnedSlice();

    // Not yet implemented:
    // - min length check and growing
    // - blocked id collisions and retry with increment

    return id;
}

test "encode" {
    const allocator = testing.allocator;

    const TestCase = struct {
        numbers: []const u64,
        alphabet: []const u8,
        expected: []const u8,
    };

    const cases = [_]TestCase{
        .{
            .numbers = &[_]u64{ 1, 2, 3 },
            .alphabet = "0123456789abcdef",
            .expected = "489158",
        },
        .{
            .numbers = &[_]u64{ 1, 2, 3 },
            .alphabet = default_alphabet,
            .expected = "86Rf07",
        },
    };

    for (cases) |case| {
        const id = try encode(allocator, case.numbers, case.alphabet);
        defer allocator.free(id);
        try testing.expectEqualStrings(case.expected, id);
    }
}

test "encode incremental numbers" {
    const allocator = testing.allocator;
    var ids = std.StringHashMap([]const u64).init(allocator);
    defer ids.deinit();

    // Incremental numbers.
    try ids.put("bM", &.{0});
    try ids.put("Uk", &.{1});
    try ids.put("gb", &.{2});
    try ids.put("Ef", &.{3});
    try ids.put("Vq", &.{4});
    try ids.put("uw", &.{5});
    try ids.put("OI", &.{6});
    try ids.put("AX", &.{7});
    try ids.put("p6", &.{8});
    try ids.put("nJ", &.{9});

    // Incremental number, same index zero.
    try ids.put("SvIz", &.{ 0, 0 });
    try ids.put("n3qa", &.{ 0, 1 });
    try ids.put("tryF", &.{ 0, 2 });
    try ids.put("eg6q", &.{ 0, 3 });
    try ids.put("rSCF", &.{ 0, 4 });
    try ids.put("sR8x", &.{ 0, 5 });
    try ids.put("uY2M", &.{ 0, 6 });
    try ids.put("74dI", &.{ 0, 7 });
    try ids.put("30WX", &.{ 0, 8 });
    try ids.put("moxr", &.{ 0, 9 });

    var iterator = ids.keyIterator();
    while (iterator.next()) |k| {
        const got = try encode(allocator, ids.get(k.*).?, default_alphabet);
        defer allocator.free(got);
        try testing.expectEqualStrings(k.*, got);
    }
}

// toID generates a new ID string for number using alphabet.
fn toID(allocator: mem.Allocator, number: u64, alphabet: []const u8) ![]const u8 {
    var result: u64 = number;

    var id = std.ArrayList(u8).init(allocator);

    while (true) {
        try id.append(alphabet[result % alphabet.len]);
        result = result / alphabet.len;
        if (result == 0) break;
    }

    const value: []u8 = try id.toOwnedSlice();

    // In the reference implementation, the letters are inserted at index 0.
    // Here we append them for efficiency, so we reverse the ID at the end.
    mem.reverse(u8, value);

    return value;
}

fn toNumber(s: []const u8, alphabet: []const u8) u64 {
    var num: u64 = 0;
    for (s) |c| {
        if (mem.indexOfScalar(u8, alphabet, c)) |i| {
            num = num * alphabet.len + i;
        }
    }
    return num;
}

test "toNumber" {
    const alphabet = [_]u8{ 'a', 'b', 'c' };
    const n = toNumber("cb", &alphabet);
    _ = n;
}

/// Shuffle shuffles inplace the given alphabet. It's consistent (produces the
/// same result given the input).
fn shuffle(alphabet: []u8) void {
    const n = alphabet.len;

    var i: usize = 0;
    var j = alphabet.len - 1;

    while (j > 0) {
        const r = (i * j + alphabet[i] + alphabet[j]) % n;
        mem.swap(u8, &alphabet[i], &alphabet[r]);
        i += 1;
        j -= 1;
    }
}

test "shuffle" {
    const allocator = testing.allocator;

    const TestCase = struct {
        input: []const u8,
        want: []const u8,
    };

    const cases = [_]TestCase{
        // Default shuffle, checking for randomness.
        // Default shuffle, checking for randomness.
        .{
            .input = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            .want = "fwjBhEY2uczNPDiloxmvISCrytaJO4d71T0W3qnMZbXVHg6eR8sAQ5KkpLUGF9",
        },
        // Numbers in the front, another check for randomness.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        // Swapping front 2 characters.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        .{
            .input = "1023456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "xI3RUayk1MSolQK7e09zYmFpVXPwHiNrdfBJ6ZAT5uCWbntgcDsEqjv4hLG28O",
        },
        // Swapping last 2 characters.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXZY",
            .want = "x038UaykZMSolIK7RzcbYmFpgXEPHiNr1d2VfGAT5uJWQetjvDswqn94hLC6BO",
        },
        // Short alphabet.
        .{
            .input = "0123456789",
            .want = "4086517392",
        },
        // Really short alphabet.
        .{
            .input = "12345",
            .want = "24135",
        },
        // Lowercase alphabet.
        .{
            .input = "abcdefghijklmnopqrstuvwxyz",
            .want = "lbfziqvscptmyxrekguohwjand",
        },
        .{
            .input = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ZXBNSIJQEDMCTKOHVWFYUPLRGA",
        },
    };

    for (cases) |case| {
        const alphabet = try allocator.alloc(u8, case.input.len);
        defer allocator.free(alphabet);

        @memcpy(alphabet, case.input);

        shuffle(alphabet);

        try testing.expectEqualSlices(u8, case.want, alphabet);
    }
}
