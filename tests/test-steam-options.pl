#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Fcntl qw(:flock);

my $helper = "$FindBin::Bin/../scripts/steam-options.pl";
my $dir = tempdir(CLEANUP => 1);
my $number = 0;
my $option = 'C:\\\\windows\\\\system32\\\\cmd.exe /d /c C:\\\\HoodWarfare2-launch.cmd %command%';
my $old = '"LaunchOptions"  "-old \\"quoted\\" C:\\\\example"';
my $fixture = <<'VDF';
// A sanitized fixture, not a Steam account export.
"UserLocalConfigStore"
{
  "Unrelated" "escaped \" quote; slash \\; newline \n"
  "Software" { "Valve" { "Steam" {
    "apps"
    {
      "999" { "LaunchOptions" "leave this alone" }
      "5155360"
      {
        /* Keep the existing binding and every comment. */
        "Controller" { "Binding" "gamepad" }
        "LaunchOptions"  "-old \"quoted\" C:\\example" // keep this too
      }
    }
    "OtherSetting" "keep"
  } } }
}
// trailing comment
VDF

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>', $path) or die $!;
    binmode($fh);
    print {$fh} $data or die $!;
    close($fh) or die $!;
}
sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die $!;
    binmode($fh);
    local $/;
    return scalar <$fh>;
}
sub input_file {
    my ($text) = @_;
    my $path = "$dir/config-" . ++$number . '.vdf';
    write_file($path, $text);
    return $path;
}
sub run_helper {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $helper, @args);
    close($in);
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout . $stderr);
}

my $file = input_file($fixture);
chmod(0640, $file) or die $!;
my ($status, $message) = run_helper('--file', $file, '--check');
is($status, 1, 'check reports configuration is needed');
is(read_file($file), $fixture, 'check never edits input');
ok(!-e "$file.hood-backup", 'check creates no backup');
($status, $message) = run_helper('--file', $file);
is($status, 0, 'updates an existing launch option') or diag($message);
my $expected = $fixture;
my $replacement = '"LaunchOptions"  "' . $option . '"';
my $count = $expected =~ s/\Q$old\E/$replacement/;
is($count, 1, 'test fixture contains exactly one replacement');
is(read_file($file), $expected, 'only targeted value changes; siblings, bindings, comments and escaping survive');
is(read_file("$file.hood-backup"), $fixture, 'backup retains the original bytes');
is((stat($file))[2] & 07777, 0640, 'replacement preserves permissions');
is((stat("$file.hood-backup"))[2] & 07777, 0640, 'backup preserves permissions');
my $inode = (stat($file))[1];
($status, $message) = run_helper('--file', $file);
is($status, 0, 'second run succeeds');
is(read_file($file), $expected, 'second run is byte-for-byte idempotent');
is((stat($file))[1], $inode, 'idempotent run does not replace the file');
is(read_file("$file.hood-backup"), $fixture, 'second run never overwrites original backup');
is((run_helper('--file', $file, '--check'))[0], 0, 'check recognizes the exact launch option');

for my $source (
    '',
    '// comment without trailing newline',
    '"UserLocalConfigStore" {}',
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "999" { "keep" "yes" } } } } } }',
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "5155360" { "keep" "yes" } } } } } }',
    "\xef\xbb\xbf\"UserLocalConfigStore\" {}\r\n",
) {
    my $path = input_file($source);
    ($status, $message) = run_helper('--file', $path);
    is($status, 0, 'creates missing path safely') or diag($message);
    is((run_helper('--file', $path, '--check'))[0], 0, 'created path parses and has the exact value');
    is(read_file("$path.hood-backup"), $source, 'missing-path backup is exact');
}

my $case_file = input_file('"userlocalconfigstore" { "SOFTWARE" { "Valve" { "Steam" { "apps" { "5155360" { "launchoptions" "old" } } } } } }');
is((run_helper('--file', $case_file))[0], 0, 'keys are matched without case sensitivity');
like(read_file($case_file), qr/"launchoptions"/, 'existing key spelling is retained');

for my $bad (
    '"UserLocalConfigStore" {',
    '"UserLocalConfigStore" { "unterminated" "oops }',
    '"UserLocalConfigStore" { "no value" }',
    '"UserLocalConfigStore" {} }',
    '/* unterminated comment',
    '"UserLocalConfigStore" "scalar"',
    '"UserLocalConfigStore" {} "USERLOCALCONFIGSTORE" {}',
    '"UserLocalConfigStore" { "Software" {} "software" {} }',
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "5155360" {} "5155360" {} } } } } }',
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "5155360" { "LaunchOptions" "one" "launchoptions" "two" } } } } } }',
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "5155360" { "LaunchOptions" {} } } } } } }',
) {
    my $path = input_file($bad);
    ($status, $message) = run_helper('--file', $path);
    is($status, 2, 'rejects malformed or ambiguous target data');
    is(read_file($path), $bad, 'rejected input remains untouched');
    ok(!-e "$path.hood-backup", 'rejection creates no backup');
}

my $link = "$dir/symlink.vdf";
symlink($file, $link) or die $!;
is((run_helper('--file', $link))[0], 2, 'refuses a symlink input');
my $backup_link_input = input_file('');
symlink($file, "$backup_link_input.hood-backup") or die $!;
is((run_helper('--file', $backup_link_input))[0], 2, 'refuses a symlink backup');
is(read_file($backup_link_input), '', 'symlink-backup refusal leaves input untouched');
my $backup_input = input_file('');
write_file("$backup_input.hood-backup", 'previous original');
is((run_helper('--file', $backup_input))[0], 0, 'existing regular backup is allowed');
is(read_file("$backup_input.hood-backup"), 'previous original', 'existing backup is never overwritten');

my $locked_input = input_file($fixture);
open(my $lock, '<', $locked_input) or die $!;
flock($lock, LOCK_EX | LOCK_NB) or die $!;
is((run_helper('--file', $locked_input))[0], 2, 'refuses a locked file without waiting');
is(read_file($locked_input), $fixture, 'locked file stays unchanged');
close($lock);
is((run_helper('--file', "$dir/not-there.vdf"))[0], 2, 'missing input returns a clear error status');
is((run_helper())[0], 2, 'missing CLI argument returns error status');

my $crlf = $fixture;
$crlf =~ s/\n/\r\n/g;
my $crlf_file = input_file("\xef\xbb\xbf" . $crlf);
is((run_helper('--file', $crlf_file))[0], 0, 'existing value in BOM and CRLF input is updated');
my $crlf_expected = $expected;
$crlf_expected =~ s/\n/\r\n/g;
is(read_file($crlf_file), "\xef\xbb\xbf" . $crlf_expected, 'BOM and CRLF bytes survive unchanged');

done_testing();
