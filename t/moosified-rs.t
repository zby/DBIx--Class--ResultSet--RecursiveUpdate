use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DBSchemaMoose;
use RunTests;

my $schema = DBSchemaMoose->get_test_schema('dbi:SQLite:dbname=:memory:');

run_tests($schema);
