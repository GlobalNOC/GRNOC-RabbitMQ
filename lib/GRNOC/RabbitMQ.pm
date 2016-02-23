#--------------------------------------------------------------------
#----- GRNOC RabbitMQ 
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#-----
#----- This is a base module for all of the other GRNOC RabbitMQ
#----- modules, the goal is to abstract away lots of the boiler plate
#----- RabbitMQ facilities to make it simpler for developers to use
#--------------------------------------------------------------------

package GRNOC::RabbitMQ;

=head1 NAME
GRNOC::RabbitMQ - GRNOC RabbitMQ Library for perl
=head1 SYNOPSIS
    use GRNOC::RabbitMQ;
print "This is version $GRNOC::RabbitMQ::VERSION\n";
=head1 DESCRIPTION
The RabbitMQ collection is a set of perl modules which are used to
provide and interact with GRNOC AMQP services

The main features of the library are:
=over
=item *
Provides easy to use interface for implementing services and service
clients that work with our systems
=item *
Provides an object oriented model for communcation with services
=item *
Consistent base for all services, using proper POD documetation, named
parameters and OO where sensible.
=back
=head1 OVERVIEW OF CLASSES AND PACKAGES
This table should give you a quick overview of the classes provided by the
library. Indentation shows class inheritance.
  GRNOC::RabbitMQ::Method    -- RabbitMQ Method handler object
  GRNOC::RabbitMQ::Dispatcher  -- RabbitMQ Dispatcher object
  GRNOC::RabbitMQ::Client  -- RabbitMQ Client ojbect interface
=head1 AUTHOR
GRNOC System Engineering, C<< <syseng at grnoc.iu.edu> >>
=head1 BUGS
Please report any bugs or feature requests via grnoc bugzilla
=head1 SUPPORT
You can find documentation for this module with the perldoc command.
    perldoc GRNOC::RabbitMQ
=cut


use strict;
use warnings;

our $VERSION = '1.0.0';

sub new {
    my $caller = shift;

    my $class = ref( $caller );
    $class = $caller if ( !$class );

    my $self = {
        @_
    };

    bless( $self, $class );

    return $self;


sub get_version{
    my $self = shift;
    return $VERSION;
}

1;
