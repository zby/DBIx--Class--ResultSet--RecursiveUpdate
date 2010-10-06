use strict;
use warnings;

package DBIx::Class::ResultSet::RecursiveUpdate;

our $VERSION = '0.013';

use base qw(DBIx::Class::ResultSet);

sub recursive_update {
    my ( $self, $updates, $fixed_fields ) = @_;
    return
        DBIx::Class::ResultSet::RecursiveUpdate::Functions::recursive_update(
        resultset    => $self,
        updates      => $updates,
        fixed_fields => $fixed_fields
        );
}

package DBIx::Class::ResultSet::RecursiveUpdate::Functions;
use Carp;
use Scalar::Util qw( blessed );
use List::MoreUtils qw/ any /;

sub recursive_update {
    my %params = @_;
    my ( $self, $updates, $fixed_fields, $object, $resolved,
        $if_not_submitted )
        = @params{
        qw/resultset updates fixed_fields object resolved if_not_submitted/};
    $resolved ||= {};

    # warn 'entering: ' . $self->result_source->from();
    carp 'fixed fields needs to be an array ref'
        if $fixed_fields && ref($fixed_fields) ne 'ARRAY';
    my %fixed_fields;
    %fixed_fields = map { $_ => 1 } @$fixed_fields if $fixed_fields;
    if ( blessed($updates) && $updates->isa('DBIx::Class::Row') ) {
        return $updates;
    }
    if ( $updates->{id} ) {
        $object = $self->find( $updates->{id}, { key => 'primary' } );
    }
    my @missing =
        grep { !exists $updates->{$_} && !exists $fixed_fields{$_} }
        $self->result_source->primary_columns;
    if ( !$object && !scalar @missing ) {

        # warn 'finding by: ' . Dumper( $updates ); use Data::Dumper;
        $object = $self->find( $updates, { key => 'primary' } );
    }
    $updates = { %$updates, %$resolved };
    @missing =
        grep { !exists $resolved->{$_} } @missing;
    if ( !$object && !scalar @missing ) {

       # warn 'finding by +resolved: ' . Dumper( $updates ); use Data::Dumper;
        $object = $self->find( $updates, { key => 'primary' } );
    }
    $object ||= $self->new( {} );

    # warn Dumper( $updates ); use Data::Dumper;
    # direct column accessors
    my %columns;

    # relations that that should be done before the row is inserted into the
    # database like belongs_to
    my %pre_updates;

    # relations that that should be done after the row is inserted into the
    # database like has_many, might_have and has_one
    my %post_updates;
    my %other_methods;
    my %columns_by_accessor = _get_columns_by_accessor($self);

    #    warn 'resolved: ' . Dumper( $resolved );
    #    warn 'updates: ' . Dumper( $updates ); use Data::Dumper;
    #    warn 'columns: ' . Dumper( \%columns_by_accessor );
    for my $name ( keys %$updates ) {
        my $source = $self->result_source;

        # columns
        if ( exists $columns_by_accessor{$name}
            && !( $source->has_relationship($name)
                && ref( $updates->{$name} ) ) )
        {

            #warn "$name is a column\n";
            $columns{$name} = $updates->{$name};
            next;
        }

        # relationships
        if ( $source->has_relationship($name) ) {
            if ( _master_relation_cond( $self, $name ) ) {

                #warn "$name is a pre-update rel\n";
                $pre_updates{$name} = $updates->{$name};
                next;
            }
            else {

                #warn "$name is a post-update rel\n";
                $post_updates{$name} = $updates->{$name};
                next;
            }
        }

        # many-to-many helper accessors
        if ( is_m2m( $self, $name ) ) {

            #warn "$name is a many-to-many helper accessor\n";
            $other_methods{$name} = $updates->{$name};
            next;
        }

        # accessors
        if ( $object->can($name) && not $source->has_relationship($name) ) {

            #warn "$name is an accessor";
            $other_methods{$name} = $updates->{$name};
            next;
        }

        # unknown
        # TODO: don't throw a warning instead of an exception to give users
        #       time to adapt to the new API
        $self->throw_exception(
            "No such column, relationship, many-to-many helper accessor or generic accessor '$name'"
        );
    }

    # warn 'other: ' . Dumper( \%other_methods ); use Data::Dumper;

    # first update columns and other accessors
    # so that later related records can be found
    for my $name ( keys %columns ) {

        #warn "update col $name\n";
        $object->$name( $columns{$name} );
    }
    for my $name ( keys %other_methods ) {

        #warn "update other $name\n";
        $object->$name( $updates->{$name} );
    }
    for my $name ( keys %pre_updates ) {

        #warn "pre_update $name\n";
        _update_relation( $self, $name, $pre_updates{$name}, $object,
            $if_not_submitted );
    }

    # $self->_delete_empty_auto_increment($object);
    # don't allow insert to recurse to related objects
    # do the recursion ourselves
    # $object->{_rel_in_storage} = 1;
    #warn "CHANGED: " . $object->is_changed . "\n":
    #warn "IN STOR: " .  $object->in_storage . "\n";
    $object->update_or_insert if $object->is_changed;
    $object->discard_changes;

    # updating many_to_many
    for my $name ( keys %$updates ) {
        next if exists $columns{$name};
        my $value = $updates->{$name};

        if ( is_m2m( $self, $name ) ) {

            #warn "update m2m $name\n";
            my ($pk) = _get_pk_for_related( $self, $name );
            my @rows;
            my $result_source = $object->$name->result_source;
            my @updates;
            if ( !defined $value ) {
                next;
            }
            elsif ( ref $value ) {
                @updates = @{$value};
            }
            else {
                @updates = ($value);
            }
            for my $elem (@updates) {
                if ( ref $elem ) {
                    push @rows,
                        recursive_update(
                        resultset => $result_source->resultset,
                        updates   => $elem
                        );
                }
                else {
                    push @rows,
                        $result_source->resultset->find( { $pk => $elem } );
                }
            }
            my $set_meth = 'set_' . $name;
            $object->$set_meth( \@rows );
        }
    }
    for my $name ( keys %post_updates ) {

        #warn "post_update $name\n";
        _update_relation( $self, $name, $post_updates{$name}, $object,
            $if_not_submitted );
    }
    return $object;
}

# returns DBIx::Class::ResultSource::column_info as a hash indexed by column accessor || name
sub _get_columns_by_accessor {
    my $self   = shift;
    my $source = $self->result_source;
    my %columns;
    for my $name ( $source->columns ) {
        my $info = $source->column_info($name);
        $info->{name} = $name;
        $columns{ $info->{accessor} || $name } = $info;
    }
    return %columns;
}

# Arguments: $rs, $name, $updates, $row, $if_not_submitted
sub _update_relation {
    my ( $self, $name, $updates, $object, $if_not_submitted ) = @_;

    # this should never happen because we're checking the paramters passed to
    # recursive_update, but just to be sure...
    $object->throw_exception("No such relationship '$name'")
        unless $object->has_relationship($name);

    #warn "_update_relation $name: OBJ: " . ref($object) . "\n";

    my $info = $object->result_source->relationship_info($name);

    # get a related resultset without a condition
    my $related_resultset =
        $self->related_resultset($name)->result_source->resultset;
    my $resolved;
    if ( $self->result_source->can('_resolve_condition') ) {
        $resolved =
            $self->result_source->_resolve_condition( $info->{cond}, $name,
            $object );
    }
    else {
        $self->throw_exception(
            "result_source must support _resolve_condition");
    }

    # warn "$name resolved: " . Dumper( $resolved ); use Data::Dumper;
    $resolved = {}
        if defined $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION
            && $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION
            == $resolved;

    my @rel_cols = keys %{ $info->{cond} };
    map {s/^foreign\.//} @rel_cols;

    #warn "REL_COLS: " . Dumper(@rel_cols); use Data::Dumper;
    my $rel_col_cnt = scalar @rel_cols;

    # find out if all related columns are nullable
    my $all_fks_nullable = 1;
    for my $rel_col (@rel_cols) {
        $all_fks_nullable = 0
            unless $related_resultset->result_source->column_info($rel_col)
                ->{is_nullable};
    }

    $if_not_submitted = $all_fks_nullable ? 'nullify' : 'delete'
        unless defined $if_not_submitted;

    #warn "\tNULLABLE: $all_fks_nullable ACTION: $if_not_submitted\n";

    #warn "RELINFO for $name: " . Dumper($info); use Data::Dumper;

    # the only valid datatype for a has_many rels is an arrayref
    if ( $info->{attrs}{accessor} eq 'multi' ) {

        # handle undef like empty arrayref
        $updates = []
            unless defined $updates;
        $self->throw_exception(
            "data for has_many relationship '$name' must be an arrayref")
            unless ref $updates eq 'ARRAY';

        my @updated_objs;

        #warn "\tupdating has_many rel '$name' ($rel_col_cnt columns cols)\n";
        for my $sub_updates ( @{$updates} ) {
            my $sub_object = recursive_update(
                resultset => $related_resultset,
                updates   => $sub_updates,
                resolved  => $resolved
            );

            push @updated_objs, $sub_object;
        }

        #warn "\tcreated and updated related rows\n";

        my @cond;
        my @related_pks = $related_resultset->result_source->primary_columns;

        my $rs_rel_delist = $object->$name;

        # foreign table has a single pk column
        if ( scalar @related_pks == 1 ) {
            $rs_rel_delist = $rs_rel_delist->search_rs(
                {   $related_pks[0] =>
                        { -not_in => [ map ( $_->id, @updated_objs ) ] }
                }
            );
        }

        # foreign table has multiple pk columns
        else {
            for my $obj (@updated_objs) {
                my %cond_for_obj;
                for my $col (@related_pks) {
                    $cond_for_obj{$col} = $obj->get_column($col);
                }
                push @cond, \%cond_for_obj;
            }
            $rs_rel_delist = $rs_rel_delist->search_rs( { -not => [@cond] } );
        }

        #warn "\tCOND: " . Dumper(\%cond);
        #my $rel_delist_cnt = $rs_rel_delist->count;
        if ( $if_not_submitted eq 'delete' ) {

            #warn "\tdeleting related rows: $rel_delist_cnt\n";
            $rs_rel_delist->delete;
        }
        elsif ( $if_not_submitted eq 'set_to_null' ) {

            #warn "\tnullifying related rows: $rel_delist_cnt\n";
            my %update = map { $_ => undef } @rel_cols;
            $rs_rel_delist->update( \%update );
        }
    }
    elsif ($info->{attrs}{accessor} eq 'single'
        || $info->{attrs}{accessor} eq 'filter' )
    {

        #warn "\tupdating rel '$name': $if_not_submitted\n";
        my $sub_object;
        if ( ref $updates ) {

            # for might_have relationship
            if ( $info->{attrs}{accessor} eq 'single'
                && defined $object->$name )
            {
                $sub_object = recursive_update(
                    resultset => $related_resultset,
                    updates   => $updates,
                    object    => $object->$name
                );
            }
            else {
                $sub_object = recursive_update(
                    resultset => $related_resultset,
                    updates   => $updates,
                    resolved  => $resolved
                );
            }
        }
        else {
            $sub_object = $related_resultset->find($updates)
                unless (
                !$updates
                && ( exists $info->{attrs}{join_type}
                    && $info->{attrs}{join_type} eq 'LEFT' )
                );
        }
        $object->set_from_related( $name, $sub_object )
            unless (
               !$sub_object
            && !$updates
            && ( exists $info->{attrs}{join_type}
                && $info->{attrs}{join_type} eq 'LEFT' )
            );
    }
    else {
        $self->throw_exception(
            "recursive_update doesn't now how to handle relationship '$name' with accessor "
                . $info->{attrs}{accessor} );
    }
}

sub is_m2m {
    my ( $self, $relation ) = @_;
    my $rclass = $self->result_class;

    # DBIx::Class::IntrospectableM2M
    if ( $rclass->can('_m2m_metadata') ) {
        return $rclass->_m2m_metadata->{$relation};
    }
    my $object = $self->new( {} );
    if (    $object->can($relation)
        and !$self->result_source->has_relationship($relation)
        and $object->can( 'set_' . $relation ) )
    {
        return 1;
    }
    return;
}

sub get_m2m_source {
    my ( $self, $relation ) = @_;
    my $rclass = $self->result_class;

    # DBIx::Class::IntrospectableM2M
    if ( $rclass->can('_m2m_metadata') ) {
        return $self->result_source->related_source(
            $rclass->_m2m_metadata->{$relation}{relation} )
            ->related_source(
            $rclass->_m2m_metadata->{$relation}{foreign_relation} );
    }
    my $object = $self->new( {} );
    my $r = $object->$relation;
    return $r->result_source;
}

sub _delete_empty_auto_increment {
    my ( $self, $object ) = @_;
    for my $col ( keys %{ $object->{_column_data} } ) {
        if ($object->result_source->column_info($col)->{is_auto_increment}
            and ( !defined $object->{_column_data}{$col}
                or $object->{_column_data}{$col} eq '' )
            )
        {
            delete $object->{_column_data}{$col};
        }
    }
}

sub _get_pk_for_related {
    my ( $self, $relation ) = @_;
    my $result_source;
    if ( $self->result_source->has_relationship($relation) ) {
        $result_source = $self->result_source->related_source($relation);
    }

    # many to many case
    if ( is_m2m( $self, $relation ) ) {
        $result_source = get_m2m_source( $self, $relation );
    }
    return $result_source->primary_columns;
}

# This function determines wheter a relationship should be done before or
# after the row is inserted into the database
# relationships before: belongs_to
# relationships after: has_many, might_have and has_one
# true means before, false after
sub _master_relation_cond {
    my ( $self, $name ) = @_;

    my $source = $self->result_source;
    my $info   = $source->relationship_info($name);

    #warn "INFO: " . Dumper($info) . "\n";

    # has_many rels are always after
    return 0
        if $info->{attrs}->{accessor} eq 'multi';

    my @foreign_ids = _get_pk_for_related( $self, $name );

    #warn "IDS: " . join(', ', @foreign_ids) . "\n";

    my $cond = $info->{cond};

    sub _inner {
        my ( $source, $cond, @foreign_ids ) = @_;

        while ( my ( $f_key, $col ) = each %{$cond} ) {

            # might_have is not master
            $col   =~ s/^self\.//;
            $f_key =~ s/^foreign\.//;
            if ( $source->column_info($col)->{is_auto_increment} ) {
                return 0;
            }
            if ( any { $_ eq $f_key } @foreign_ids ) {
                return 1;
            }
        }
        return 0;
    }

    if ( ref $cond eq 'HASH' ) {
        return _inner( $source, $cond, @foreign_ids );
    }

    # arrayref of hashrefs
    elsif ( ref $cond eq 'ARRAY' ) {
        for my $new_cond (@$cond) {
            return _inner( $source, $new_cond, @foreign_ids );
        }
    }
    else {
        $source->throw_exception(
            "unhandled relation condition " . ref($cond) );
    }
    return;
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

DBIx::Class::ResultSet::RecursiveUpdate - like update_or_create - but recursive

=head1 SYNOPSIS

The functional interface:

    my $new_item = DBIx::Class::ResultSet::RecursiveUpdate::Functions::recursive_update({ 
        resultset => $schema->resultset( 'Dvd' ),
        updates => {
            id => 1, 
            owned_dvds => [ 
                { 
                  title => 'One Flew Over the Cuckoo's Nest' 
                } 
            ] 
        }
    });


As ResultSet subclass:

    __PACKAGE__->load_namespaces( default_resultset_class => '+DBIx::Class::ResultSet::RecursiveUpdate' );

in the Schema file (see t/lib/DBSchema.pm).  Or appriopriate 'use base' in the ResultSet classes. 

Then:

    my $user = $user_rs->recursive_update( { 
        id => 1, 
        owned_dvds => [ 
        { 
          title => 'One Flew Over the Cuckoo's Nest' 
        } 
        ] 
      }
    );

  
=head1 DESCRIPTION

This is still experimental. I've added a functional interface so that it can be used 
in Form Processors and not require modification of the model.

You can feed the ->create method with a recursive datastructure and have the related records
created.  Unfortunately you cannot do a similar thing with update_or_create - this module
tries to fill that void. 

It is a base class for ResultSets providing just one method: recursive_update
which works just like update_or_create but can recursively update or create
data objects composed of multiple rows. All rows need to be identified by primary keys
- so you need to provide them in the update structure (unless they can be deduced from 
the parent row - for example when you have a belongs_to relationship).  
If not all colums comprising the primary key are specified - then a new row will be created,
with the expectation that the missing columns will be filled by it (as in the case of auto_increment 
primary keys).  


If the resultset itself stores an assignement for the primary key, 
like in the case of:
    
    my $restricted_rs = $user_rs->search( { id => 1 } );

then you need to inform recursive_update about additional predicate with a second argument:

    my $user = $restricted_rs->recursive_update( { 
        owned_dvds => [ 
        { 
          title => 'One Flew Over the Cuckoo's Nest' 
        } 
        ] 
      },
      [ 'id' ]
    );

This will work with a new DBIC release.

For a many_to_many (pseudo) relation you can supply a list of primary keys
from the other table - and it will link the record at hand to those and
only those records identified by them.  This is convenient for handling web
forms with check boxes (or a SELECT box with multiple choice) that let you
update such (pseudo) relations.  

For a description how to set up base classes for ResultSets see load_namespaces
in DBIx::Class::Schema.

=head1 DESIGN CHOICES

Columns and relationships which are excluded from the updates hashref aren't
touched at all.

=head2 Treatment of belongs_to relations

In case the relationship is included but undefined in the updates hashref,
all columns forming the relationship will be set to null.
If not all of them are nullable, DBIx::Class will throw an error.

Updating the relationship:

    my $dvd = $dvd_rs->recursive_update( {
        id    => 1,
        owner => $user->id,
    });

Clearing the relationship (only works if cols are nullable!):

    my $dvd = $dvd_rs->recursive_update( {
        id    => 1,
        owner => undef,
    });

=head2 Treatment of might_have relationships

In case the relationship is included but undefined in the updates hashref,
all columns forming the relationship will be set to null.

Updating the relationship:

    my $user = $user_rs->recursive_update( {
        id => 1,
        address => {
            street => "101 Main Street",
            city   => "Podunk",
            state  => "New York",
        }
    });

Clearing the relationship:

    my $user = $user_rs->recursive_update( {
        id => 1,
        address => undef,
    });

=head2 Treatment of has_many relations

If a relationship key is included in the data structure with a value of undef
or an empty array, all existing related rows will be deleted, or their foreign
key columns will be set to null.

The exact behaviour depends on the nullability of the foreign key columns and
the value of the "if_not_submitted" parameter. The parameter defaults to
undefined which neither nullifies nor deletes.

When the array contains elements they are updated if they exist, created when
not and deleted if not included.

=head3 All foreign table columns are nullable

In this case recursive_update defaults to nullifying the foreign columns.

=head3 Not all foreign table columns are nullable

In this case recursive_update deletes the foreign rows.

Updating the relationship:

    Passing ids:

    my $dvd = $dvd_rs->recursive_update( {
        id   => 1,
        tags => [1, 2],
    });

    Passing hashrefs:

    my $dvd = $dvd_rs->recursive_update( {
        id   => 1,
        tags => [
            {
                id   => 1,
                file => 'file0'
            },
            {
                id   => 2,
                file => 'file1',
            },
        ],
    });

    Passing objects:

    TODO

    You can even mix them:

    my $dvd = $dvd_rs->recursive_update( {
        id   => 1,
        tags => [ '2', { id => '3' } ],
    });

Clearing the relationship:

    my $dvd = $dvd_rs->recursive_update( {
        id   => 1,
        tags => undef,
    });

    This is the same as passing an empty array:

    my $dvd = $dvd_rs->recursive_update( {
        id   => 1,
        tags => [],
    });

=head2 Treatment of many-to-many pseudo relations

The function gets the information about m2m relations from DBIx::Class::IntrospectableM2M.
If it isn't loaded in the ResultSource classes the code relies on the fact that:

    if($object->can($name) and
             !$object->result_source->has_relationship($name) and
             $object->can( 'set_' . $name )
         )

Then $name must be a many to many pseudo relation.
And that in a similarly ugly was I find out what is the ResultSource of
objects from that many to many pseudo relation.


=head1 INTERFACE 

=head1 METHODS

=head2 recursive_update

The method that does the work here.

=head2 is_m2m

$self->is_m2m( 'name ' ) - answers the question if 'name' is a many to many
(pseudo) relation on $self.

=head2 get_m2m_source

$self->get_m2m_source( 'name' ) - returns the ResultSource linked to by the many
to many (pseudo) relation 'name' from $self.


=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT

DBIx::Class::RecursiveUpdate requires no configuration files or environment variables.

=head1 DEPENDENCIES

    DBIx::Class

=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-dbix-class-recursiveput@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Zbigniew Lukasiak  C<< <zby@cpan.org> >>
Influenced by code by Pedro Melo.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2008, Zbigniew Lukasiak C<< <zby@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
