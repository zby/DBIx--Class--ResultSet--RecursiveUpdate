# -*- perl -*-

use lib 't/lib';
use DBSchema;
use RunTests;
use Test::More;

my ($dsn, $user, $pass) = @ENV{map { "DBICTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_PG_DSN}, _USER and _PASS to run this test'
 . ' (note: creates and tables!)' unless ($dsn && $user);

plan tests => 19;

my $schema = DBSchema::get_test_schema( $dsn, $user, $pass );

run_tests( $schema );

