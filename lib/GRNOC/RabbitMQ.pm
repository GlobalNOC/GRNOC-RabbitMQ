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

sub connect_to_rabbit{
    my %args = ( host => 'localhost',
		 port => 5672,
		 user => undef,
		 pass => undef,
		 vhost => undef,
		 timeout => 10,
		 on_success => GRNOC::RabbitMQ::on_success_handler,
		 on_failure => GRNOC::RabbitMQ::on_failure_handler,
		 on_read_failure => GRNOC::RabbitMQ::on_read_failure_hander,
		 on_return => GRNOC::RabbitMQ::on_return_handler,
		 on_close => GRNOC:RabbitMQ::on_close_handler	
		 @_);
    
    my $cv = AnyEvent->condvar;
    my $rabbit_mq;
    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
        host => $args{'host'},
        port => $args{'port'},
        user => $args{'user'},
        pass => $args{'pass'},
        vhost => $args{'vhost'},
        timeout => $args{'timeout'},
        tls => 0,
        on_success => $args{'on_success'},		
        on_failure => $args{'on_failure'},
        on_read_failure => $args{'on_read_failure'},
        on_return  => $args{'on_return'},
        on_close   => $args{'on_close'}
	);

    return $ar;
}



1;
