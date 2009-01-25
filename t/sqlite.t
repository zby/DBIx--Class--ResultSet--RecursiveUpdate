# -*- perl -*-

use lib 't/lib';
use DBSchema;
use RunTests;
use Test::More;
plan tests => 19;

my $schema = DBSchema::get_test_schema();
run_tests( $schema );

