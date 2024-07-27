const std = @import("std");
const stdin = std.io.getStdIn().reader();
const print = std.debug.print;
const allocator = std.heap.page_allocator;

const Words = struct {
    const Self = @This();
    arena: std.heap.ArenaAllocator,
    // The game of Wordle tells us which of the letters we guessed are not part
    // of the word at all, so we can make sure not to waste time searching for
    // words containing these.
    available: []const u8,
    // When we guess a letter in the correct position, Wordle lets us know this
    // as well by displaying it as green. No need to search for any words that
    // don't have these letters in their known positions.
    known: [5]?u8,
    // When we guess a letter that is in the word, but not in the position we
    // guessed it to be in, Wordle displays it as yellow. We can ignore all
    // words that have these letters in their incorrect positions as well.
    banned: [5][]const u8,
    // Using `known` and `banned`, we can infer which letters are guaranteed to
    // be in the word, so we can ignore all words that don't contain each of
    // them. In some cases, the player can know that a letter exists in the
    // word more than once. For simplicity, we ignore this case.
    forced: ?[]const u8,
    // By keeping track of how many of the letters we have tried for each
    // position, we know when to try the next letter (when the next position
    // has been exhausted) as well when to stop (when the first position has
    // been exhausted).
    tried: [5]u5,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        var arena_alloc = arena.allocator();

        var available = try arena_alloc.alloc(u8, 26);
        var avail_stream = std.io.fixedBufferStream(&available);
        var avail_writer = avail_stream.writer();
        print("Which letters are still available? ", .{});
        try stdin.streamUntilDelimiter(&avail_writer, '\n', 26);

        var known = [_]?u8{null} ** 5;
        for (0..5) |i| known[i] = try Self.askLetter(i);

        var banned: [5][]const u8 = undefined;
        for (0..5) |i| {
            var buf = arena_alloc.alloc(u8, 26);
            var buf_stream = std.io.fixedBufferStream(&buf);
            var buf_writer = buf_stream.writer();
            print("Which letters are banned in position {d}? ", .{i + 1});
            try stdin.streamUntilDelimiter(&buf_writer, '\n', 26);
            banned[i] = buf[0..try buf_stream.getEndPos()];
        }

        var forced: [26]u8 = undefined;
        var f_len: usize = 0;
        for (known) |letter| f_len += addForced(&forced, f_len, letter);
        for (banned) |letter| f_len += addForced(&forced, f_len, letter);

        return .{
            .arena = arena,
            .available = available[0..try avail_stream.getEndPos()],
            .known = known,
            .banned = banned,
            .forced = forced[0..f_len],
            .tried = [1]u5{0} ** 5,
        };
    }

    fn addForced(forced: *[26]u8, len: usize, letter: ?u8) usize {
        const l = letter orelse return 0;
        if (len > 0) for (forced[0..len]) |f| if (f == l) return 0;
        forced[len] = l;
        return 1;
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    fn askLetter(index: usize) !?u8 {
        var buf = [1]?u8{null};

        print("Type letter in position {d} if known, else hit enter: ", .{index + 1});
        var writer = std.io.fixedBufferStream(&buf).writer();
        try stdin.streamUntilDelimiter(&writer, '\n', 1);

        return buf[0];
    }
};

pub fn main() !void {
    var buf: [27]u8 = undefined;
    const available = try askInput("Which letters are still available? ", &buf) orelse unreachable;
    var options: [5]usize = .{available.len + 1} ** 5;

    var known: [5]u8 = undefined;
    for (0..5) |i| {
        const letter = try askLetter(i);
        if (letter != ' ') options[i] = 1;
        known[i] = letter;
    }

    var banned: [5][]const u8 = undefined;
    var bufs: [5][26]u8 = undefined;
    for (0..5) |i| {
        print("Which letters are banned in position {d}? ", .{i + 1});
        const to_ban = try askInput("", &bufs[i]) orelse unreachable;
        options[i] -= to_ban.len;
        banned[i] = to_ban;
    }

    var buf2: [27]u8 = undefined;
    const forced = try askInput("Which letters have to be used? ", &buf2) orelse unreachable;

    var total: usize = 1;
    for (options) |single| {
        total *= single;
    }

    var words = try allocator.alloc(?[5]u8, total);
    var next_word: usize = 0;
    words[next_word] = null;
    for (available) |first| {
        var word: [5]u8 = undefined;
        if (banned[0].len > 0 and contains(banned[0], first)) continue;
        word[0] = if (known[0] == ' ') first else known[0];
        for (available) |second| {
            if (banned[1].len > 0 and contains(banned[1], second)) continue;
            word[1] = if (known[1] == ' ') second else known[1];
            for (available) |third| {
                if (banned[2].len > 0 and contains(banned[2], third)) continue;
                word[2] = if (known[2] == ' ') third else known[2];
                for (available) |fourth| {
                    if (banned[3].len > 0 and contains(banned[3], fourth)) continue;
                    word[3] = if (known[3] == ' ') fourth else known[3];
                    for (available) |fifth| {
                        if (banned[4].len > 0 and contains(banned[4], fifth)) continue;
                        word[4] = if (known[4] == ' ') fifth else known[4];
                        var legal = true;
                        for (forced) |l| {
                            if (!contains(&word, l)) legal = false;
                        }
                        if (legal and !contains_word(words, &word)) {
                            words[next_word] = word;
                            next_word += 1;
                            if (words.len > next_word) {
                                words[next_word] = null;
                            }
                        }
                    }
                }
            }
        }
    }

    for (words) |word| {
        if (word) |w| print("{s}\n", .{w}) else break;
    }
}

fn askInput(question: []const u8, buf: []u8) !?[]const u8 {
    print("{s} ", .{question});
    return stdin.readUntilDelimiterOrEof(buf[0..], '\n');
}

fn askLetter(index: usize) !u8 {
    print("Type letter in position {d} if known, else hit enter: ", .{index + 1});
    var buf: [2]u8 = undefined;
    const input = try stdin.readUntilDelimiterOrEof(buf[0..], '\n') orelse " ";
    return if (input.len > 0) input[0] else ' ';
}

fn contains(word: []const u8, letter: u8) bool {
    for (word) |l| {
        if (letter == l) return true;
    }
    return false;
}

fn contains_word(words: []?[5]u8, word: []const u8) bool {
    for (words) |maybe_word| {
        if (maybe_word) |*w| if (std.mem.eql(u8, word, w)) return true;
    }
    return false;
}
