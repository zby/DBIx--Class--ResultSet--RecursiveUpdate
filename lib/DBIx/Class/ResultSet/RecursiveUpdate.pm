package DBIx::Class::ResultSet::RecursiveUpdate;

use version; $VERSION = qv('0.001');

use warnings;
use strict;
use Carp;
use Scalar::Util qw( blessed );

use base qw(DBIx::Class::ResultSet);

sub recursive_update {
    my ( $self, $updates, $fixed_fields ) = @_;
    # warn 'entering: ' . $self->result_source->from();

    carp 'fixed fields needs to be an array ref' if $fixed_fields && ref($fixed_fields) ne 'ARRAY';
    my %fixed_fields;
    %fixed_fields = map { $_ => 1 } @$fixed_fields if $fixed_fields;

    if ( blessed($updates) && $updates->isa('DBIx::Class::Row') ) {
        return $updates;
    }


    # direct column accessors
    my %columns;

    # relations that that should be done before the row is inserted into the database
    # like belongs_to
    my %pre_updates;

    # relations that that should be done after the row is inserted into the database
    # like has_many and might_have
    my %post_updates;
    my %columns_by_accessor = $self->_get_columns_by_accessor;

    for my $name ( keys %$updates ) {
        my $source = $self->result_source;
        if ( $columns_by_accessor{$name}
            && !( $source->has_relationship($name) && ref( $updates->{$name} ) )
          )
        {
            $columns{$name} = $updates->{$name};
            next;
        }
        next if !$source->has_relationship($name);
        my $info = $source->relationship_info($name);
        if (
            _master_relation_cond(
                $source, $info->{cond}, $self->_get_pk_for_related($name)
            )
          )
        {
            $pre_updates{$name} = $updates->{$name};
        }
        else {
            $post_updates{$name} = $updates->{$name};
        }
    }
    # warn 'columns: ' . Dumper( \%columns ); use Data::Dumper;

    my $object;
    my @missing =
      grep { !exists $columns{$_} && !exists $fixed_fields{$_} } $self->result_source->primary_columns;
    if ( !scalar @missing ) {
        $object = $self->find( \%columns, { key => 'primary' } );
    }
    $object ||= $self->new( {} );

# first update columns and other accessors - so that later related records can be found
    for my $name ( keys %columns ) {
        $object->$name( $updates->{$name} );
    }
    for my $name ( keys %pre_updates ) {
        my $info = $object->result_source->relationship_info($name);
        $self->_update_relation( $name, $updates, $object, $info );
    }
    $self->_delete_empty_auto_increment($object);

# don't allow insert to recurse to related objects - we do the recursion ourselves
#    $object->{_rel_in_storage} = 1;
    $object->update_or_insert;

    # updating many_to_many
    for my $name ( keys %$updates ) {
        next if exists $columns{$name};
        my $value = $updates->{$name};

        if ( $self->is_m2m($name) ) {
            my ($pk) = $self->_get_pk_for_related($name);
            my @rows;
            my $result_source = $object->$name->result_source;
            for my $elem ( @{ $updates->{$name} } ) {
                if ( ref $elem ) {
                    push @rows, $result_source->resultset->find($elem);
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
        my $info = $object->result_source->relationship_info($name);
        $self->_update_relation( $name, $updates, $object, $info );
    }
    return $object;
}

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

sub _update_relation {
    my ( $self, $name, $updates, $object, $info ) = @_;

    my $related_result =
      $self->related_resultset($name)->result_source->resultset;
    my $resolved =
      $self->result_source->resolve_condition( $info->{cond}, $name, $object );

 #                    warn 'resolved: ' . Dumper( $resolved ); use Data::Dumper;
    $resolved = undef
      if defined $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION && $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION == $resolved;
    if ( ref $updates->{$name} eq 'ARRAY' ) {
        for my $sub_updates ( @{ $updates->{$name} } ) {
            $sub_updates = { %$sub_updates, %$resolved } if $resolved && ref( $sub_updates ) eq 'HASH';
            my $sub_object =
              $related_result->recursive_update( $sub_updates );
        }
    }
    else {
        my $sub_updates = $updates->{$name};
        $sub_updates = { %$sub_updates, %$resolved } if $resolved && ref( $sub_updates ) eq 'HASH';
        my $sub_object =
          $related_result->recursive_update( $sub_updates );
        $object->set_from_related( $name, $sub_object );
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
        if (
            $object->result_source->column_info($col)->{is_auto_increment}
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
    if ( $self->is_m2m($relation) ) {
        $result_source = $self->get_m2m_source($relation);
    }
    return $result_source->primary_columns;
}

sub _master_relation_cond {
    my ( $source, $cond, @foreign_ids ) = @_;
    my $foreign_ids_re = join '|', @foreign_ids;
    if ( ref $cond eq 'HASH' ) {
        for my $f_key ( keys %{$cond} ) {

            # might_have is not master
            my $col = $cond->{$f_key};
            $col =~ s/self\.//;
            if ( $source->column_info($col)->{is_auto_increment} ) {
                return 0;
            }
            if ( $f_key =~ /^foreign\.$foreign_ids_re/ ) {
                return 1;
            }
        }
    }
    elsif ( ref $cond eq 'ARRAY' ) {
        for my $new_cond (@$cond) {
            return 1
              if _master_relation_cond( $source, $new_cond, @foreign_ids );
        }
    }
    return;
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

DBIx::Class::ResultSet::RecursiveUpdate - like update_or_create - but recursive 


=head1 VERSION

This document describes DBIx::Class::ResultSet::RecursiveUpdate version 0.001


=head1 SYNOPSIS

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


For a many_to_many (pseudo) relation you can supply a list of primary keys
from the other table - and it will link the record at hand to those and
only those records identified by them.  This is convenient for handling web
forms with check boxes (or a SELECT box with multiple choice) that let you
update such (pseudo) relations.

For a description how to set up base classes for ResultSets see load_namespaces
in DBIx::Class::Schema.

=head1 DESIGN CHOICES

=head2 Treatment of many to many pseudo relations

The function gets the information about m2m relations from DBIx::Class::IntrospectableM2M.
If it is not loaded in the ResultSource classes - then the code relies on the fact that:
    if($object->can($name) and
             !$object->result_source->has_relationship($name) and
             $object->can( 'set_' . $name )
         )

then $name must be a many to many pseudo relation.  And that in a
similarly ugly was I find out what is the ResultSource of objects from
that many to many pseudo relation.


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

=for author to fill in:

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:

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
