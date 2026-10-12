#!/usr/bin/perl
use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock :mode O_NOFOLLOW);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptions);

# Steam must be stopped before calling this helper. No Steam/game data belongs
# in this repository: the only input is the user's own localconfig.vdf.
my $launch = 'C:\\windows\\system32\\cmd.exe /d /c C:\\HoodWarfare2-launch.cmd %command%';
my @path = qw(UserLocalConfigStore Software Valve Steam apps 5155360 LaunchOptions);
my ($file, $check);
Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
if (!GetOptions('file=s' => \$file, 'check' => \$check) || !defined($file) || @ARGV) {
    print STDERR "Usage: perl steam-options.pl --file PATH [--check]\n";
    exit 2;
}

my $temp_path;
my $exit = eval { run(); };
if ($@) {
    my $error = $@;
    unlink $temp_path if defined $temp_path;
    $error =~ s/\s+\z//;
    print STDERR "steam-options: $error\n";
    exit 2;
}
exit $exit;

sub run {
    my @before = lstat($file);
    @before && S_ISREG($before[2])
        or die "Input must be an existing regular file (not a symlink).\n";
    sysopen(my $input, $file, O_RDONLY | O_NOFOLLOW)
        or die "Cannot open input: $!\n";
    binmode($input);
    flock($input, ($check ? LOCK_SH : LOCK_EX) | LOCK_NB)
        or die "Input is locked by another process. Stop Steam and retry.\n";
    my @opened = stat($input);
    same_file(\@before, \@opened)
        or die "Input changed while it was being opened.\n";
    my $source = read_all($input);
    my $parser = { source => $source, offset => 0, size => length($source) };
    $parser->{offset} = 3 if substr($source, 0, 3) eq "\xef\xbb\xbf";
    my $root = parse_object($parser, 0, 0);
    my ($parent, $missing, $leaf) = ($root, undef, undef);
    for my $index (0 .. $#path) {
        my @matches = grep { lc($_->{key}) eq lc($path[$index]) } @{$parent->{children}};
        @matches <= 1
            or die "Ambiguous duplicate key at " . join('/', @path[0 .. $index]) . ".\n";
        if (!@matches) { $missing = $index; last; }
        $leaf = $matches[0];
        if ($index < $#path) {
            $leaf->{object}
                or die "Expected an object at " . join('/', @path[0 .. $index]) . ".\n";
            $parent = $leaf->{object};
        } else {
            !$leaf->{object} or die "LaunchOptions must be a string, not an object.\n";
        }
    }
    if (!defined($missing) && $leaf->{value} eq $launch) {
        print "Hood Warfare 2 launch options are already configured.\n";
        return 0;
    }
    if ($check) {
        print "Hood Warfare 2 launch options need configuration.\n";
        return 1;
    }

    my $updated = $source;
    if (!defined($missing)) {
        substr($updated, $leaf->{value_start}, $leaf->{value_end} - $leaf->{value_start}, quote_vdf($launch));
    } else {
        my $newline = $source =~ /\r\n/ ? "\r\n" : "\n";
        my $position = $parent->{close};
        my $last_newline = rindex($source, "\n", $position - 1);
        my $line_start = $last_newline + 1;
        my $before_close = substr($source, $line_start, $position - $line_start);
        my $at_indent = $before_close =~ /\A[\t ]*\z/;
        # Insert at the start of the closing-brace line when possible. Existing
        # comments and whitespace remain byte-for-byte intact.
        $position = $line_start if $parent->{nested} && $at_indent;
        my $depth = $missing;
        my $addition = '';
        $addition .= $newline if $position > 0 && substr($source, $position - 1, 1) ne "\n";
        for my $index ($missing .. $#path) {
            $addition .= ("\t" x $depth) . quote_vdf($path[$index]);
            if ($index == $#path) {
                $addition .= "\t\t" . quote_vdf($launch) . $newline;
            } else {
                $addition .= $newline . ("\t" x $depth) . '{' . $newline;
                ++$depth;
            }
        }
        for (my $index = $#path - 1; $index >= $missing; --$index) {
            --$depth;
            $addition .= ("\t" x $depth) . '}' . $newline;
        }
        $addition .= "\t" x ($missing - 1) if $parent->{nested} && !$at_indent && $missing > 0;
        substr($updated, $position, 0, $addition);
    }

    # Validate the generated file before writing anything.
    my $updated_start = substr($updated, 0, 3) eq "\xef\xbb\xbf" ? 3 : 0;
    parse_object({ source => $updated, offset => $updated_start, size => length($updated) }, 0, 0);
    my $backup = "$file.hood-backup";
    my @backup_stat = lstat($backup);
    if (@backup_stat) {
        S_ISREG($backup_stat[2]) or die "Backup path is not a regular file; refusing to follow it.\n";
    } else {
        sysopen(my $backup_file, $backup, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, $opened[2] & 0777)
            or die "Cannot create backup: $!\n";
        binmode($backup_file);
        my $backup_ok = eval {
            print {$backup_file} $source or die "Cannot write backup: $!\n";
            chmod($opened[2] & 07777, $backup_file) or die "Cannot preserve backup permissions: $!\n";
            close($backup_file) or die "Cannot finish backup: $!\n";
            1;
        };
        if (!$backup_ok) {
            my $error = $@;
            close($backup_file);
            unlink($backup);
            die $error;
        }
    }
    my $output;
    ($output, $temp_path) = tempfile('.' . basename($file) . '.hood-XXXXXXXX', DIR => dirname($file), UNLINK => 0);
    binmode($output);
    print {$output} $updated or die "Cannot write temporary file: $!\n";
    chmod($opened[2] & 07777, $output) or die "Cannot preserve file permissions: $!\n";
    close($output) or die "Cannot finish temporary file: $!\n";
    my @current = lstat($file);
    same_file(\@opened, \@current) && $opened[7] == $current[7] && $opened[9] == $current[9]
        or die "Input changed during configuration; no changes were applied. Stop Steam and retry.\n";
    seek($input, 0, 0) or die "Cannot recheck input: $!\n";
    my $latest = read_all($input);
    $latest eq $source
        or die "Input changed during configuration; no changes were applied. Stop Steam and retry.\n";
    rename($temp_path, $file) or die "Cannot atomically replace input: $!\n";
    undef $temp_path;
    close($input);
    print "Configured Hood Warfare 2 launch options. Original backup: $backup\n";
    return 0;
}

sub same_file {
    my ($left, $right) = @_;
    return @$left && @$right && S_ISREG($right->[2]) && $left->[0] == $right->[0] && $left->[1] == $right->[1];
}

sub read_all {
    my ($handle) = @_;
    my $data = '';
    while (1) {
        my $count = sysread($handle, my $chunk, 65536);
        defined($count) or die "Cannot read input: $!\n";
        last if $count == 0;
        $data .= $chunk;
    }
    return $data;
}

sub quote_vdf {
    my ($value) = @_;
    $value =~ s/([\\"])/\\$1/g;
    $value =~ s/\n/\\n/g;
    $value =~ s/\r/\\r/g;
    $value =~ s/\t/\\t/g;
    return '"' . $value . '"';
}

sub skip_space {
    my ($p) = @_;
    while ($p->{offset} < $p->{size}) {
        pos($p->{source}) = $p->{offset};
        if ($p->{source} =~ /\G(?:\s+|\/\/[^\r\n]*)/gc) {
            $p->{offset} = pos($p->{source});
            next;
        }
        if (substr($p->{source}, $p->{offset}, 2) eq '/*') {
            my $end = index($p->{source}, '*/', $p->{offset} + 2);
            $end >= 0 or die "Malformed VDF: unterminated comment.\n";
            $p->{offset} = $end + 2;
            next;
        }
        last;
    }
}

sub token {
    my ($p) = @_;
    skip_space($p);
    $p->{offset} < $p->{size} or return;
    my $start = $p->{offset};
    my $first = substr($p->{source}, $p->{offset}++, 1);
    return { kind => $first, start => $start, end => $p->{offset} } if $first eq '{' || $first eq '}';
    my $value = '';
    if ($first eq '"') {
        my %escape = (n => "\n", r => "\r", t => "\t", '\\' => '\\', '"' => '"');
        while ($p->{offset} < $p->{size}) {
            my $char = substr($p->{source}, $p->{offset}++, 1);
            return { kind => 'string', value => $value, start => $start, end => $p->{offset} } if $char eq '"';
            if ($char eq '\\') {
                $p->{offset} < $p->{size} or die "Malformed VDF: unfinished escape.\n";
                my $next = substr($p->{source}, $p->{offset}++, 1);
                $value .= exists($escape{$next}) ? $escape{$next} : '\\' . $next;
            } else {
                $char ne "\0" or die "Malformed VDF: NUL byte.\n";
                $value .= $char;
            }
        }
        die "Malformed VDF: unterminated string.\n";
    }
    $value = $first;
    while ($p->{offset} < $p->{size}) {
        my $char = substr($p->{source}, $p->{offset}, 1);
        last if $char =~ /[\s{}]/;
        $char ne '"' && $char ne "\0" or die "Malformed VDF: invalid unquoted token.\n";
        $value .= $char;
        ++$p->{offset};
    }
    $first ne "\0" or die "Malformed VDF: NUL byte.\n";
    return { kind => 'string', value => $value, start => $start, end => $p->{offset} };
}

sub parse_object {
    my ($p, $nested, $depth) = @_;
    $depth <= 128 or die "Malformed VDF: nesting limit exceeded.\n";
    my $object = { children => [], nested => $nested };
    while (1) {
        my $key = token($p);
        if (!defined($key)) {
            !$nested or die "Malformed VDF: missing closing brace.\n";
            $object->{close} = $p->{offset};
            return $object;
        }
        if ($key->{kind} eq '}') {
            $nested or die "Malformed VDF: unexpected closing brace.\n";
            $object->{close} = $key->{start};
            return $object;
        }
        $key->{kind} eq 'string' or die "Malformed VDF: expected a key.\n";
        my $value = token($p);
        defined($value) && $value->{kind} ne '}' or die "Malformed VDF: missing value.\n";
        my $node = { key => $key->{value}, start => $key->{start} };
        if ($value->{kind} eq '{') {
            $node->{object} = parse_object($p, 1, $depth + 1);
        } else {
            $node->{value} = $value->{value};
            $node->{value_start} = $value->{start};
            $node->{value_end} = $value->{end};
        }
        push @{$object->{children}}, $node;
    }
}
