# -*- perl -*-

use lib 't/lib';
use DBSchemaMoose;
use RunTests;
use Test::More;

my $schema = DBSchemaMoose->get_test_schema();

run_tests( $schema);

