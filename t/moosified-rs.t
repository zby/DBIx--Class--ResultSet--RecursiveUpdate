use strict;
use warnings;
use Test::More;

BEGIN {
    eval {
        require Moose;
        require MooseX::NonMoose;
        require namespace::autoclean;
    };
    plan skip_all =>
        "Moose, MooseX::NonMoose and namespace::autoclean required"
        if $@;
}

use lib 't/lib';
use DBSchemaMoose;
use RunTests;

my $schema = DBSchemaMoose->get_test_schema('dbi:SQLite:dbname=:memory:');

run_tests($schema);
