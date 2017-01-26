#--------------------------------------------------------------------
#----- GRNOC RabbitMQ Dispatcher Library
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#----- 
#----- This module wraps much of the common Rabbit related to code
#----- especially for RPC server side, and creating methods
#----- reasonably easy to develop with.
#--------------------------------------------------------------------

use strict;
use warnings;

package GRNOC::RabbitMQ::Dispatcher;

use AnyEvent;
use GRNOC::Log;
use GRNOC::RabbitMQ;
use Moo;

=head1 NAME

GRNOC::RabbitMQ::Dispatcher - GRNOC centric RabbitMQ RPC Dispatcher

=head1 SYNOPSIS

This modules provides AMQP programmers with an abstracted JSON/AMQP base 
object.  The object handles the taks of input/param validation.

It takes care of handling the response back to the caller over Rabbit.

Here is an example of how to use this

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;

sub main{

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(queue => "OF-FWDCTL",
                                                      topic => "OF.FWDCTL",
                                                      exchange => 'OESS',
                                                      user => 'guest',
                                                      pass => 'guest');

    my $method = GRNOC::RabbitMQ::Method->new( name => "plus",
                                               callback => \&do_plus,
                                               description => "Add numbers a and b together" );
    $method->set_schema_validator( schema => {} );

    $method->add_input_parameter( name => 'a',
                                  description => 'first addend',
                                  pattern => '^(-?[0-9]+)$' );

    $method->add_input_parameter( name => 'b',
                                  description => 'second addend',
                                  pattern => '^(-?[0-9]+)$' );

    $dispatcher->register_method( $method );

    $dispatcher->start_consuming();
}

sub do_plus{
    my ($method_obj,$params,$state) = @_;

    my $a = $params->{'a'}{'value'};
    my $b = $params->{'b'}{'value'};

    return { result => ($a+$b) };
}

main();

=cut

=head2 BUILD

=head2 Constructor Arguments / Attributes
=item port
=item user
=item pass
=item host
=item vhost
=item timeout
=item queue_name
=item topic
=item exchange
=item auto_reconnect
=item on_success
=item on_failure
=item on_read_failure
=item on_return
=item on_close

=head2 Internal Objects
=item logger
=item connected
=item channel
=item queue
=item consuming
=item consuming_condvar
=item ar
=item state

=cut

has port => (is => 'rwp', default => 5672, documentation => "Port to connect to RabbitMQ server", required => 1);
has user => (is => 'rwp', default => 'guest', required => 1);
has pass => (is => 'rwp', required => 1);
has host => (is => 'rwp', default => 'localhost', required => 1);
has vhost => (is => 'rwp', default => '/', required => 1);
has timeout => (is => 'rwp', default => 15, required => 1);
has queue_name => (is => 'rwp', required => 0);
has topic => (is => 'rwp', required => 1);
has exchange => (is => 'rwp', required => 1);
has auto_reconnect => (is => 'rw', default => 0);
has on_success => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::channel_creator }, required => 1);
has on_failure => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_read_failure => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_return => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_failure_handler}, required => 1);
has on_close => (is => 'rwp', default => sub { return \&GRNOC::RabbitMQ::on_client_close_handler}, required => 1);

has logger => (is => 'rwp');

has ar => (is => 'rwp');
has connected => (is => 'rwp');
has channel => (is => 'rwp');
has queue => (is => 'rwp');
has consuming => (is => 'rwp');
has methods => (is => 'rwp', default => sub { return {} });
has consuming_condvar => (is => 'rwp');
has state => (is => 'rwp');

sub BUILD{
    my ($self) = @_;
    
    
    $self->_set_logger(GRNOC::Log->get_logger("GRNOC::RabbitMQ::Dispatcher"));

    $self->logger->error("Dispatcher connecting to RabbitMQ");
    
    $self->_set_connected(0);
    $self->_connect_to_rabbit();

    $self->logger->error("Connected: " . $self->connected);

    #--- register the help method
    my $help_method = GRNOC::RabbitMQ::Method->new(
        name         => "help",
        description  => "The help method!",
        is_default   => 1,
        callback     => \&help,
        );
    
    $help_method->set_schema_validator(
        schema => { 'type' => 'object',
                    'properties' => { "method_name" => {'type' => 'string'} }}
        );
    
    $self->register_method($help_method);
    
    
    return $self;
    
}

sub _connect_to_rabbit{
    my $self = shift;
    $self->logger->debug("Connecting to RabbitMQ.");

    my $ar = GRNOC::RabbitMQ::connect_to_rabbit(
        host => $self->host,
        port => $self->port,
        user => $self->user,
        pass => $self->pass,
        vhost => $self->vhost,
        timeout => $self->timeout,
        tls => 0,
        exchange => $self->exchange,
        type => 'topic',
        obj => $self,
        exclusive => 0,
        queue => $self->queue_name,
        on_success => $self->on_success,
        on_failure => $self->on_failure,
        on_read_failure => $self->on_read_failure,
        on_return => $self->on_return,
        on_close => $self->on_close
        );
    $self->_set_ar($ar);

    if (!$self->connected) {
        $self->logger->error("Unable to connect to RabbitMQ");
        return undef;
    }
    $self->logger->info("Connected to RabbitMQ.");

    my $dispatcher = $self;
    my $status     = AnyEvent->condvar;
    $self->channel->consume( queue      => $self->queue,
                             no_ack     => 0,
                             on_success => sub {
                                 $self->logger->info("Consuming messages from RabbitMQ.");
                                 $status->send(1);
                             },
                             on_failure => sub {
                                 $self->logger->error("Unable to consume messages from RabbitMQ.");
                                 $status->send(0);
                             },
                             on_consume => sub {
                                 my $message = shift;
                                 $dispatcher->handle_request($message);
                                 $self->channel->ack();
                             } );

    my $ok = $status->recv();
    if (!$ok) {
        return undef;
    }

    return 1;
}

=head2 help()
returns list of avail methods or if parameter 'method_name' provided, the details about that method
=cut
sub help{
    my $m_ref   = shift;
    my $params  = shift;

    my %results;

    my $method_name = $params->{'method_name'}{'value'};
    my $dispatcher = $m_ref->get_dispatcher();

    $dispatcher->logger->error("WHAT");

    if (!defined $method_name) {
	return $dispatcher->get_method_list();
    }
    else {
	my $help_method = $dispatcher->get_method($method_name);
	if (defined $help_method) {
	    return $help_method->help();
	}
	else {
	    $m_ref->set_error("unknown method: $method_name\n");
	    return undef;
	}
    }
}


#----- formats results in JSON then seddts proper cache directive header and off we go
sub _return_error{
    my $self        = shift;
    my $reply_to    = shift;
    my $rabbit_mq_connection = $self->channel;

    my %error;

    $error{"error"} = 1;
    $error{'error_text'} = $self->get_error();
    $error{'results'} = undef;
    
    if(!defined($reply_to->{'routing_key'})){
	$rabbit_mq_connection->ack();
	return;

    }
    
    $rabbit_mq_connection->publish( exchange => $reply_to->{'exchange'},
				    routing_key => $reply_to->{'routing_key'},
				    header => {'correlation_id' => $reply_to->{'correlation_id'}},
				    body => JSON::XS::encode_json(\%error));
    $rabbit_mq_connection->ack();
    
}


=head2 handle_request

=cut

sub handle_request{
    my $self = shift;
    my $var = shift;

    my $state = $self->state;
    my $reply_to = {};


    if(defined($var->{'header'}->{'no_reply'}) && $var->{'header'}->{'no_reply'} == 1){

	$self->logger->debug("No Reply specified");
	
    }else{
	$self->logger->debug("Has reply specified");
	$reply_to->{'exchange'} = $var->{'deliver'}->{'method_frame'}->{'exchange'};
	$reply_to->{'correlation_id'} = $var->{'header'}->{'correlation_id'},
	$reply_to->{'routing_key'} = $var->{'header'}->{'reply_to'};
    }

    my $method = $var->{'deliver'}->{'method_frame'}->{'routing_key'};
    
    if(!defined($method)){
	$method = "help";
    }
    
    #--- check for properly formed method
    if (!defined $method) {
	$self->_set_error("format error with method name");
	$self->_return_error($reply_to);
	return undef
    }

    #--- check for method being defined
    if (!defined $self->methods->{$method}) {
        $self->logger->error("Unknown Method: " . $method);
	$self->_set_error("unknown method: $method");
	$self->_return_error($reply_to);
	return undef;
    }
    
    #--- have the method do its thing;
    $self->methods->{$method}->handle_request( $self->channel,
                                               $reply_to,
                                               $var->{'body'}->{'payload'},
                                               $self->{'default_input_validators'},
                                               $state);

    return 1;
}


=head2 get_method_list()
Method to retrives the list of registered methods
=cut

sub get_method_list{
    my $self        = shift;

    my @methods =  sort keys %{$self->methods};
    return \@methods;

}


=head2 get_method($name)
returns method ref based upon specified name
=cut

sub get_method{
    my $self        = shift;
    my $name  = shift;
    
    return $self->methods->{$name};
}



=head2 get_error()
gets the last error encountered or undef.
=cut

sub get_error{
    my $self  = shift;
    return $self->{'error'};
}


=head2 _set_error()
protected method which sets a new error and prints it to stderr
=cut

sub _set_error{
    my $self  = shift;
    my $error = shift;

    $self->logger->error($error);
    $self->{'error'} = $error;
}


=head2 register_method()

This is used to register a web service method.  Three items are needed
to register a method: a method name, a function callback and a method configuration.
The callback will accept one input argument which will be a reference to the arguments
structure for that method, with the "value" attribute added.
The callback should return a pointer to the results data structure.

=cut
sub register_method{
    my $self  = shift;
    my $method_ref  = shift;

    return if(!$self->connected);

    my $topic = $self->topic;
    if(defined($method_ref->{'topic'})){
        $topic = $method_ref->{'topic'};
    }

    $method_ref->update_name( $topic . "." .  $method_ref->get_name());
    
    my $method_name = $method_ref->get_name();
    
    if (!defined $method_name) {
	$self->logger->error(ref $method_ref."->get_name() returned undef");
	return;
    }

    if (defined $self->methods->{$method_name}) {
	$self->logger->error("$method_name already exists");
	return;
    }

    $self->logger->error("Method Name: " . $method_name);

    $self->methods->{$method_name} = $method_ref;
    if ($method_ref->{'is_default'}) {
	$self->{'default_method'} = $method_name;
    }

    #--- set the Dispatcher reference
    $method_ref->set_dispatcher($self);

    my $cv = AnyEvent->condvar;

    $self->logger->debug("Binding $method_name to queue");

    $self->channel->bind_queue( queue => $self->queue,
                                exchange => $self->exchange,
                                routing_key => $method_ref->get_name(),
                                on_success => sub {
                                    $cv->send();
                                } );

    $cv->recv;
    return 1;
}


=head2 start_consuming

please note that start_consuming will block forever in your application

=cut

sub start_consuming{
    my $self = shift;
    $self->_set_consuming(1);    
    $self->_set_consuming_condvar(AnyEvent->condvar);
    $self->consuming_condvar->recv();
}

=head2 stop_consuming

=cut

sub stop_consuming{
    my $self = shift;
    $self->_set_consuming(0);
    $self->consuming_condvar->send();
}

1;
