#--------------------------------------------------------------------
#----- GRNOC RabbitMQ Method
#-----
#----- Copyright(C) 2015 The Trustees of Indiana University
#--------------------------------------------------------------------
#----- This module creates an RPC method callable on a RabbitMQ queue
#----- part of that involves the ability to parse JSONSchemas and
#----- proper error handling, so the developers don't have to
#--------------------------------------------------------------------

package GRNOC::RabbitMQ::Method;

use strict;
use warnings;

use AnyEvent::RabbitMQ;
use AnyEvent;
use GRNOC::Log;
use JSON::XS;
use JSON::Schema;

=head1 NAME

GRNOC::RabbitMQ::Method - a GRNOC centric RabbitMQ method Object

used to embody a registered method with its input, documentaiton,
and any other pertinent information

=head1 SYNOPSIS

This module provides AMQP programmers a methd to represent a
AMQP service which is then registered with GRNOC::RabbitMQ::Dispatcher
 
here is an example


use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;

sub main{

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(queue => "OF.FWDCTL",
                                                      exchange => 'OESS',
                                                      user => 'guest',
                                                      pass => 'guest');

    my $method = GRNOC::RabbitMQ::Method->new( name => "do_stuff",
                                               callback => \&do_stuff,
                                               description => "Does stuff" );
    $method->set_schema_validator( schema => {});

    $dispatcher->register_method( $method );

    $dispatcher->start_consuming();
}

sub do_stuff{
    my $json = shift;

    warn "\o/ it just works\n";

    return {success => 1};
}

main();

=cut

sub new{
    my $that = shift;
    my $class = ref($that) || $that;
    
    my %valid_parameter_list = (
	'name' => 1,
	'callback' => 1,
	'is_default' => 1,
	'debug' => 1,
	'description' => 1,
	'output_formatter' => 1,
	'logger' => 1,
	);
    
    #--- overide the defaults
    my %args = (
	output_formatter => sub { JSON::XS->new()->encode( shift ) },
	name             => undef,
	callback         => undef,
	description      => undef,
	debug            => 0,
	@_,
	);

    my $self = \%args;

    $self->{'logger'} = GRNOC::Log->get_logger();

    bless $self,$class;

    # validate the parameter list
    
    # only valid parameters
    foreach my $passed_param (keys %$self) {
	if (!(exists $valid_parameter_list{$passed_param})) {
	    $self->{'logger'}->confess("invalid parameter [$passed_param]");
	    return;
	}
    }
    # missing required parameters
    if (!defined $self->{'name'}) {
	$self->{'logger'}->confess("methods need a name");
	return;
    }
    if (!defined $self->{'description'}) {
	$self->{'logger'}->confess("methods need a description");
	return;
    }
    if (!defined $self->{'callback'}) {
	$self->{'logger'}->confess("need to define a proper callback");
	return;
    }
    
    return $self;
}

=head2 get_name()
returns the registerd method name for this method object.
=cut

sub get_name{
    my $self  = shift;
    return $self->{'name'};
}

sub set_schema_validator{
    my $self = shift;
    my %params = @_;
    if(!defined($params{'schema'})){
	$self->{'logger'}->error("No Schema specified for the schema validator");
	return;
    }

    my $validator = JSON::Schema->new($params{'schema'});
    if(!defined($validator)){
	
    }

    $self->{'validator'} = $validator;
}

sub _validate_schema{
    my $self = shift;
    my $body = shift;

    my $json;
    eval{
	$json = decode_json($body);
    };
    
    if(!defined($json)){
	$self->set_error("Is not valid JSON: " . $body);
	return;
    }

    my $res = $self->{'validator'}->validate($json);
    if($res){
	$self->{'logger'}->debug("JSON Validated!");
	return 1;
    }else{

	my $error_str = "";
	foreach my $error (@{$res->errors}){
	    $error_str .= $error . "\n";
	}

	$self->set_error("JSON did not validate against the specified Schema because: " . $error_str);
	return;
    }
}

sub help{
    
}


=head2 get_error()
gets the last error encountered or undef.
=cut

sub get_error{
    my $self        = shift;
    return $self->{'error'};
}

=head2 set_error()
method which sets a new error and prints it to stderr
Can also be used by callback to signal error to client.
=cut

sub set_error{
    my $self        = shift;
    my $error       = shift;

    $self->{'logger'}->error($error);
    $self->{'error'}  = $error;
}


=head2 get_dispatcher()
gets the associated Dispatcher reference
=cut

sub get_dispatcher{
    my $self        = shift;
    return $self->{'dispatcher'};
}


=head2 set_dispatcher()
Sets the dispatcher reference
=cut

sub set_dispatcher{
    my $self             = shift;
    my $dispatcher       = shift;

    $self->{'dispatcher'} = $dispatcher;
}


=head2 _return_results()
 protected method for formatting callback results and setting httpd response headers
=cut


#----- formats results in JSON then sets proper cache directive header and off we go
sub _return_results{
    my $self     = shift;
    my $rabbit_mq_channel = shift;
    my $reply_to = shift;
    my $results = shift;

    $rabbit_mq_channel->publish( exchange => $reply_to->{'exchange'},
				 routing_key => $reply_to->{'routing_key'},
				 header => {'correlation_id' => $reply_to->{'correlation_id'}},
				 body => JSON::XS::encode_json($results));
}

=head2 _return_error()
 protected method for formatting callback results and setting httpd response headers
=cut


#----- formats results in JSON then seddts proper cache directive header and off we go
sub _return_error{
    my $self                = shift;
    my $rabbit_mq_channel   = shift;
    my $reply_to            = shift;

    my %error;

    $error{"error"}   = 1;
    $error{'error_text'}  = $self->get_error();
    $error{'results'}   = undef;

    #--- would be nice if client could pass a output format param and select between json and xml?
    
    $rabbit_mq_channel->publish( exchange => $reply_to->{'exchange'},
				 routing_key => $reply_to->{'routing_key'},
				 header => {'correlation_id' => $reply_to->{'correlation_id'}},
				 body => JSON::XS::encode_json(\%error));
}



=head2 handle_request()
 method called by dispatcher when a request comes in, passes
 a cgi object reference, a file handle, and a state reference.
=cut

sub handle_request {
    my ( $self, $rabbit_mq_channel, $reply_to, $body ) = @_;

    my $res = $self->_validate_schema($body);
    if (!defined $res) {
	$self->_return_error($rabbit_mq_channel, $reply_to);
	return;
    }

    #--- call the callback
    my $callback    = $self->{'callback'};
    my $results     = &$callback($self,decode_json($body));
    
    if (!defined $results) {
	$self->_return_error($rabbit_mq_channel, $reply_to);
	return;
    }
    else {
    #--- return results
	$self->_return_results($rabbit_mq_channel, $reply_to, $results);
	return 1;
    }
}

1;

