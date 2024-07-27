const std = @import("std");
const stdin = std.io.getStdIn().reader();
const print = std.debug.print;

const WordleError = error{NoAvailableLetters};

const Words = struct {
    const Self = @This();
    arena: ?std.heap.ArenaAllocator = null,
    // The game of Wordle tells us which of the letters we guessed are not part
    // of the word at all, so we can make sure not to waste time searching for
    // words containing these.
    available: []const u8 = "",
    // When we guess a letter in the correct position, Wordle lets us know this
    // as well by displaying it as green. No need to search for any words that
    // don't have these letters in their known positions.
    known: [5]?u8 = [_]?u8{null} ** 5,
    // When we guess a letter that is in the word, but not in the position we
    // guessed it to be in, Wordle displays it as yellow. We can ignore all
    // words that have these letters in their incorrect positions as well.
    banned: [5][]const u8 = [_][]const u8{""} ** 5,
    // Using `known` and `banned`, we can infer which letters are guaranteed to
    // be in the word, so we can ignore all words that don't contain each of
    // them. In some cases, the player can know that a letter exists in the
    // word more than once. For simplicity, we ignore this case.
    forced: ?[]const u8 = null,
    // By keeping track of how many of the letters we have tried for each
    // position, we know when to try the next letter (when the next position
    // has been exhausted) as well when to stop (when the first position has
    // been exhausted).
    to_try: [5]u5 = [_]u5{0} ** 5,
    // Before words can be returned, some initial setup needs to happen, moving
    // the `to_try` indices to their initial positions, and avoiding to skip the
    // first word.
    set_up: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var alloc = arena.allocator();

        var available = try alloc.alloc(u8, 26);
        var avail_stream = std.io.fixedBufferStream(available[0..]);
        const avail_writer = avail_stream.writer();
        print("Which letters are still available? ", .{});
        try stdin.streamUntilDelimiter(avail_writer, '\n', 27);

        var known = [_]?u8{null} ** 5;
        for (0..5) |i| known[i] = try Self.askLetter(i);

        var banned: [5][]const u8 = undefined;
        for (0..5) |i| {
            var buf = try alloc.alloc(u8, 26);
            var buf_stream = std.io.fixedBufferStream(buf[0..]);
            const buf_writer = buf_stream.writer();
            print("Which letters are banned in position {d}? ", .{i + 1});
            try stdin.streamUntilDelimiter(buf_writer, '\n', 27);
            banned[i] = buf[0..buf_stream.pos];
        }

        return .{
            .arena = arena,
            .available = available[0..avail_stream.pos],
            .known = known,
            .banned = banned,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.arena) |arena| arena.deinit();
    }

    pub fn next(self: *Self) !?[5]u8 {
        if (!self.set_up) {
            try self.setUp();
        } else if (try self.advanceLetter(0)) return null;
        while (self.forcedMissing()) {
            if (try self.advanceLetter(0)) return null;
        }
        return self.currentWord();
    }

    fn askLetter(index: usize) !?u8 {
        var buf = [_]u8{' '} ** 2;

        print("Type letter in position {d} if known, else hit enter: ", .{index + 1});
        var stream = std.io.fixedBufferStream(buf[0..]);
        const writer = stream.writer();
        try stdin.streamUntilDelimiter(writer, '\n', 2);

        return if (buf[0] == ' ') null else buf[0];
    }

    fn setUp(self: *Self) !void {
        var forced = try self.arena.?.allocator().alloc(u8, 5);
        var f_len: usize = 0;
        for (self.known) |letter| f_len += addForced(forced, f_len, letter);
        for (self.banned) |letters| {
            for (letters) |letter| f_len += addForced(forced, f_len, letter);
        }
        self.forced = forced[0..f_len];

        for (0..5) |i| _ = try self.advanceLoop(i);
        self.set_up = true;
    }

    fn addForced(forced: []u8, len: usize, letter: ?u8) usize {
        const l = letter orelse return 0;
        if (len > 0) for (forced[0..len]) |f| if (f | 32 == l | 32) return 0;
        forced[len] = l | 32;
        return 1;
    }

    /// Recursive function: If called with the final position value, 4, the
    /// corresponding `to_try` index is advanced to the next legal letter. If
    /// it advances past the final available letter, it wraps back around to
    /// the first legal letter, returning true to signal the previous letter to
    /// advance as well.
    fn advanceLetter(self: *Self, pos: usize) !bool {
        // If the letter in the current position is known, whether or not the
        // previous letter should advance is determined by whether the next
        // letter wraps. If the final letter is known, the previous letter
        // should always advance.
        if (self.known[pos]) |_| {
            return if (pos == 4) true else try self.advanceLetter(pos + 1);
        }
        if (pos < 4 and !try self.advanceLetter(pos + 1)) return false;
        self.to_try[pos] += 1;

        return try self.advanceLoop(pos);
    }

    fn advanceLoop(self: *Self, pos: usize) !bool {
        var wrapped = false;
        if (self.to_try[pos] >= self.available.len) {
            self.to_try[pos] = 0;
            wrapped = true;
        }
        while (true) {
            if (self.to_try[pos] >= self.available.len) {
                self.to_try[pos] = 0;
                // If we already wrapped once, but then wrap again, none of the
                // available letters are legal in this position.
                wrapped = if (!wrapped) true else return error.NoAvailableLetters;
            } else if (self.illegalInPosition(pos)) {
                self.to_try[pos] += 1;
            } else break;
        }
        return wrapped;
    }

    fn illegalInPosition(self: Self, pos: usize) bool {
        if (self.known[pos]) |known| {
            if (self.available[self.to_try[pos]] | 32 != known | 32) return true;
        }
        for (self.banned[pos]) |banned| {
            if (banned | 32 == self.available[self.to_try[pos]] | 32) return true;
        } else return false;
    }

    fn forcedMissing(self: Self) bool {
        var still_required: usize = self.forced.?.len;
        for (self.forced.?) |fl| {
            for (self.currentWord()) |wl| if (wl | 32 == fl | 32) {
                still_required -= 1;
                break;
            };
        }
        return still_required != 0;
    }

    fn currentWord(self: Self) [5]u8 {
        var word: [5]u8 = undefined;
        for (0..5) |i| word[i] = (self.available[self.to_try[i]] | 32) - 32;
        return word;
    }
};

pub fn main() !void {
    var buf: [26 * 7]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    var words = try Words.init(allocator);
    defer words.deinit();

    while (try words.next()) |word| print("{s}\n", .{word});
}
