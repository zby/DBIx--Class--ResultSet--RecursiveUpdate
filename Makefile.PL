use strict;
use warnings;
use inc::Module::Install 0.91;

name 'DBIx-Class-ResultSet-RecursiveUpdate';
author 'Zbigniew Lukasiak';
all_from 'lib/DBIx/Class/ResultSet/RecursiveUpdate.pm';
license 'perl';

repository 'http://github.com/zby/DBIx--Class--ResultSet--RecursiveUpdate/tree/master';

# prereqs
requires 'DBIx::Class' => '0.08100';
requires 'DBIx::Class::IntrospectableM2M';
requires 'SQL::Translator' => '0.11005';
requires 'DateTime';
requires 'DBD::SQLite' => '1.21';
requires 'Readonly' => '1.03';

# things the tests need
test_requires 'Test::More'      => '0.88';

tests();

auto_install();

WriteAll();

