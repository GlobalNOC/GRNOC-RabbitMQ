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

use lib '/opt/grnoc/venv/perl-GRNOC-RabbitMQ/lib/perl5';

use AnyEvent::RabbitMQ 1.19;
use AnyEvent 7.07;
use GRNOC::Log;
use JSON::XS 3.01;
use JSON::Schema 0.016;
use GRNOC::WebService::Regex;
use Storable 2.45 qw(dclone);

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
	'topic' => 1,
	'callback' => 1,
	'is_default' => 1,
	'debug' => 1,
	'description' => 1,
	'output_formatter' => 1,
	'logger' => 1,
	'async' => 1,
	);
    
    #--- overide the defaults
    my %args = (
	output_formatter => sub { JSON::XS->new()->encode( shift ) },
	name             => undef,
	callback         => undef,
	description      => undef,
	debug            => 0,
	topic            => undef,
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
    
    $self->set_schema_validator( schema => { });

    
    return $self;
}

=head2 get_name()
returns the registerd method name for this method object.
=cut

sub get_name{
    my $self  = shift;
    return $self->{'name'};
}

=head2 update_name

=cut

sub update_name{
    my $self = shift;
    my $name = shift;

    $self->{'name'} = $name;
    return;
}

=head2 set_schema_validator

=cut

=head2 set_schema_validator

Please note that this blows away any parameters specified through add_input_parameter

=cut

sub set_schema_validator{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'schema'})){
        $self->{'logger'}->error("No Schema specified for the schema validator");
        return;
    }

    my $validator = JSON::Schema->new( $params{'schema'});
    if(!defined($validator)){
        $self->set_error("Unable to create a validator based on schema: " . $params{'schema'});
        return;
    }

    #ok presuming we made it this far... we need to parse the first chunk and add input parameters for it
    if(defined $validator->schema->{'type'} && $validator->schema->{'type'} eq 'object'){
        foreach my $key (keys (%{$validator->schema->{'properties'}})){
            $self->{'input_params'}{$key}{'schema'} = $validator->schema->{'properties'}{$key};
        }
    }

    $self->{'validator'} = $validator;
    return 1;

}


sub _set_schema_validator{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'schema'})){
	$self->{'logger'}->error("No Schema specified for the schema validator");
	return;
    }

    my $validator = JSON::Schema->new( $params{'schema'});
    if(!defined($validator)){
	$self->set_error("Unable to create a validator based on schema: " . $params{'schema'});
	return;
    }

    $self->{'validator'} = $validator;
    return 1;
}

sub _build_schema{
    my $self = shift;
    
    my @required;
    my $schema = {};

    $schema->{'type'} = "object";
    $schema->{'$schema'} = "http://json-schema.org/draft-04/schema#";
    $schema->{'description'} = "Dynamically generated!";
    $schema->{'additionalProperties'} = 0;

    foreach my $param (sort keys(%{$self->{'input_params'}})) {
	my $pattern                         = $self->{'input_params'}{$param}{'pattern'};
	my $required                        = $self->{'input_params'}{$param}{'required'};
	my $schema_validator                = $self->{'input_params'}{$param}{'schema'};

	if($required){
	    push(@required, $param);
	}

	if(defined($schema_validator) && !defined($pattern)){
	    $schema->{'properties'}{$param} = $schema_validator
	}else{
	    $schema->{'properties'}{$param} = {'type' => 'any'}
	}
        if($required){
            $schema->{'properties'}{$param}->{'required'} = 1;
        }
    }
    
    $schema->{'required'} = \@required;
    return encode_json($schema);
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

    if(!defined($self->{'validator'})){
	$self->set_error("No validator found!");
	return;
    }

    my $res = $self->{'validator'}->validate($json);

    if($res){
	$self->{'logger'}->debug("JSON Validated!");
	return 1;
    }else{
        
	my $error_str = "";
	foreach my $error ($res->errors){
	    $error_str .= $error->{'property'} . " " . $error->{'message'};
	}

	$self->set_error("JSON did not validate against the specified Schema because: " . $error_str);
	return;
    }
}

=head2 add_input_parameter

=cut

sub add_input_parameter{
    my $self = shift;
    my %params = @_;

    my %args = (
	pattern   => '^(\d+)$',
	required  => 1,
	multiple  => 0,
	ignore_default_input_validators => 0,
	input_validators => [],
	min_length => undef,
	max_length => undef,
	validation_error_text => undef,
	schema => undef,
	@_,
	);

    if (!exists $args{'allow_null'}) {
	if ($args{'required'}) {
	    $args{'allow_null'} = 0;
	}
	else {
	    $args{'allow_null'} = 1;
	}
    }
    
    if (!defined $args{'name'}) {
	$self->{'logger'}->confess("name is a required parameter");
	return;
    }

    if (!defined $args{'description'}) {
	$self->{'logger'}->confess("description is a required parameter");
	return;
    }

    if (!defined $args{'validation_error_text'} && defined($args{'pattern'})){
	my $error_text;
	my $pattern = $args{'pattern'};
	my $name    = $args{'name'};

	if ($pattern eq $GRNOC::WebService::Regex::NUMBER_ID){
	    $error_text = "Parameter $name only accepts positive integers and 0.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::BOOLEAN) {
	    $error_text = "Parameter $name only accepts either 0 or 1 for false or true values, respectively.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::FLOAT){
	    $error_text = "Parameter $name only accepts floating point numbers.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::INTEGER){
	    $error_text = "Parameter $name only accepts integer numbers.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::ANY_NUMBER){
	    $error_text = "Parameter $name only accepts numbers.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::NAME_ID){
	    $error_text = "Parameter $name only accepts printable characters. This excludes control characters like newlines, carrier return, and others.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::TEXT){
	    $error_text = "Parameter $name only accepts printable characters and spaces, including newlines. This excludes control characters.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::IP_ADDRESS){
	    $error_text = "Parameter $name only accepts valid IPv4 or IPv6 addresses, including valid shortened notation.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::MAC_ADDRESS){
	    $error_text = "Parameter $name only accepts valid MAC addresses using either a : or a - as delimiter.";
	}
	elsif ($pattern eq $GRNOC::WebService::Regex::HOSTNAME){
	    $error_text = "Parameter $name only accepts valid RFC1123 host/domain names.";
	}
	else {
	    $error_text = "CGI input parameter $name does not match pattern /$pattern/ ";
	}

	$args{'validation_error_text'} = $error_text;
    }

    $self->{'input_params'}{$args{'name'}} = \%args;

    my $new_schema = $self->_build_schema();
    $self->_set_schema_validator( schema => $new_schema );

    return 1;
}


=head2 remove_input_parameter()
removes a input parameter from this method.
=cut

sub remove_input_parameter{
    my $self  = shift;
    my $param = shift;

    if (defined $self->{'input_params'}{$param}) {
	delete $self->{'input_params'}{$param};
	
	my $new_schema = $self->_build_schema();
	$self->_set_schema_validator( schema => $new_schema );
	
	return 1;
    }

    return;
}

=head2 add_input_validator()
This method takes a name, description, subroutine callback, and the name of an input parameter as arguments.  This
subroutine should return either a true or false value which states whether or not the supplied input to a particular
parameter is sane (true) or tainted (false).  An error will be returned unless every input supplied to the parameter
returns a true value when executed with every input validator supplied.  All default input validators defined in the
dispatcher must also return a true value, unless they are overridden with the ignore_default_input_validators => 1
argument in the add_input_parameter() method.
=cut

sub add_input_validator {

    my ( $self, %args ) = @_;

    my $name = $args{'name'};
    my $description = $args{'description'};
    my $callback = $args{'callback'};
    my $input_parameter = $args{'input_parameter'};

    my $input_validators = $self->{'input_params'}{$input_parameter}{'input_validators'};

    my $validator = {'name' => $name,
                   'description' => $description,
		     'callback' => $callback};

    push( @$input_validators, $validator );
}


=head2 help

=cut

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

Protected method for formatting RPC results. Historically the
GlobalNOC has placed RPC results in an array under the results key of
a hash; This is no longer the case. RPC results are now wrapped in a
parent hash under the 'results' key; An array is not provided to the
caller.

Formats results in JSON then sets proper cache directive header and
off we go.

    {
        results => $results
    }

=cut
sub _return_results{
    my $self     = shift;
    my $rabbit_mq_channel = shift;
    my $reply_to = shift;
    my $results = shift;

    if(!defined($reply_to->{'routing_key'})){
	$rabbit_mq_channel->ack();
	return;
    }

    $results = {results => $results};

    my $json = encode_json($results);

    $rabbit_mq_channel->publish(
        exchange => $reply_to->{'exchange'},
        routing_key => $reply_to->{'routing_key'},
        header => {'correlation_id' => $reply_to->{'correlation_id'}},
        body => $json
    );
    $rabbit_mq_channel->ack();

}

=head2 _return_error()

Protected method for formatting RPC errors. RPC error results are
wrapped in a parent hash under the 'error' key.

Formats results in JSON then seddts proper cache directive header and
off we go.

    {
        error => $results
    }

=cut
sub _return_error{
    my $self              = shift;
    my $rabbit_mq_channel = shift;
    my $reply_to          = shift;
    my $results           = shift;

    my %error;

    if (!defined $results) {
        $error{"error"} = $self->get_error();
    } else {
        $error{"error"} = $results;
    }

    if (!defined($reply_to->{'routing_key'})) {
        $rabbit_mq_channel->ack();
        return;
    }

    my $json;
    eval {
        $json = JSON::XS::encode_json(\%error);
    };
    if ($@) {
        $error{"error"} = "$@";
    }

    $rabbit_mq_channel->publish(
        exchange => $reply_to->{'exchange'},
        routing_key => $reply_to->{'routing_key'},
        header => {'correlation_id' => $reply_to->{'correlation_id'}},
        body => $json
    );
    $rabbit_mq_channel->ack();
}


sub _parse_input_parameters{
    my $self = shift;
    my $inputs = shift;
    my $default_input_validators = shift;

    foreach my $param (sort keys(%{$self->{'input_params'}})) {

	my $pattern                         = $self->{'input_params'}{$param}{'pattern'};
	my $required                        = $self->{'input_params'}{$param}{'required'};
	my $multiple                        = $self->{'input_params'}{$param}{'multiple'};
	my $default                         = $self->{'input_params'}{$param}{'default'};
	my $ignore_default_input_validators = $self->{'input_params'}{$param}{'ignore_default_input_validators'};
	my $input_validators                = $self->{'input_params'}{$param}{'input_validators'};
	my $min_length                      = $self->{'input_params'}{$param}{'min_length'};
	my $max_length                      = $self->{'input_params'}{$param}{'max_length'};
	my $allow_null                      = $self->{'input_params'}{$param}{'allow_null'};
	my $attachment                      = $self->{'input_params'}{$param}{'attachment'};
	my $validation_error_text           = $self->{'input_params'}{$param}{'validation_error_text'};
	my $schema                          = $self->{'input_params'}{$param}{'schema'};

	my $input = $inputs->{$param};

	if($schema){
	    $self->{'input_params'}{$param}{'is_set'} = 1;
	    $self->{'input_params'}{$param}{'value'} = $input;
	    next;
	}

	my @input_array;
	if(ref($input) eq 'ARRAY'){
	    if(scalar @{$input} == 0){
		if (ref($default) eq "ARRAY") {
		    @input_array = @$default;
		}else {
		    $input_array[0] = $default;
		}
	    }else{
		@input_array = @{$input};
	    }
	}else{
	    if(!defined($input)){
		$input_array[0] = $default;
	    }else{
		$input_array[0] = $input;
	    }
	}
	
	# clear out existing array, if any, to avoid infinitely growing arrays in a mod_perl environment
	undef($self->{'input_params'}{$param}{'value'});
	$self->{'input_params'}{$param}{'is_set'} = 0;
	
	# perform the proper input validation on every supplied argument to this parameter
	foreach my $input (@input_array) {
	    
	    # ISSUE=8595 strip all leading and trailing whitespace if not attachment
	    $input =~ s/^\s+|\s+$//g if ( defined( $input ) && !$attachment );
	    
	    # value not supplied for parameter
	    if ( !defined( $input ) ) {
		
		# it was a required parameter
		if ( $required ) {
		    
		    $self->set_error( $self->{'name'}.": required input parameter $param is missing " );
		    return undef;
		}
	    }
	    
	    # value was given for parameter
	    else {
		
		$self->{'input_params'}{$param}{'is_set'} = 1;
		
		# handle NULL parameters
		if ( $input eq "" ) {
		    if ( !$allow_null ) {
			$self->set_error( $self->{'name'}.": input parameter $param cannot be NULL " );
			return undef;
		    }
		    
		    if ( $multiple ) {
			push( @{$self->{'input_params'}{$param}{'value'}}, undef );
		    }
		    else {
			$self->{'input_params'}{$param}{'value'} = undef;
		    }
		}
		
		#--- parameter exists
		elsif ( $input eq "" || # dont pattern match on a NULL value
			( !$attachment && Encode::decode( 'UTF-8', $input ) =~ /$pattern/ ) || # if its not an attachment, decode UTF-8 first
			( $attachment && $input =~ /$pattern/ ) ) { # its an attachment, do not decode UTF-8
		    
		    my $input_value = $1;
		    my $filename = undef;
		    my $mime_type = undef;
		    
		    # re-encode back to UTF-8 if not an attachment
		    $input_value = Encode::encode( 'UTF-8', $input_value ) if ( !$attachment );
		    
		    if (defined($min_length) && length($input) < $min_length) {
			$self->set_error( $self->{'name'} . ": input parameter $param is shorter than the specified minimum length of $min_length." );
			return undef;
		    }
		    if (defined($max_length) && length($input) > $max_length) {
			$self->set_error( $self->{'name'} . ": input parameter $param is longer than the specified maximum length of $max_length." );
			return undef;
		    }
		    
		    # make sure this input parameter validates against every default input validator subroutine
		    if ( !$ignore_default_input_validators ) {
			
			foreach my $default_input_validator ( @$default_input_validators ) {
			    
			    my $callback = $default_input_validator->{'callback'};
			    
			    # execute the input validator subroutine, passing in the inputs to this parameter
			    my $is_valid = &$callback( $self, $input );
			    
			    if ( !$is_valid ) {
				
				$self->set_error( $self->{'name'} . ": input parameter $param does not pass default input validators." );
				return undef;
			    }
			}
		    }
		    
		    # make sure this input parameter validates any specific input validators
		    foreach my $input_validator ( @$input_validators ) {
			
			my $callback = $input_validator->{'callback'};
			
			my $is_valid = &$callback( $self, $input );
			
			if ( !$is_valid ) {
			    
			    $self->set_error( $self->{'name'} . ": input parameter $param does not pass input validators." );
			    return undef;
			}
		    }
		    
		    if ($multiple) {      

			push(@{$self->{'input_params'}{$param}{'value'}},$input_value);
		    }
		    else {
			$self->{'input_params'}{$param}{'value'} = $input_value;
		    }
		    
		    if ($self->{'debug'}) {
			warn "- setting $param == $input_value\n";
		    }
		}
		else {
		    
		    $self->set_error($self->{'name'} . ': ' . $validation_error_text);
		    return undef;
		    
		}
		
	    }
	}
	
    }
    return 1;
}

=head2 handle_request()
 method called by dispatcher when a request comes in, passes
 a cgi object reference, a file handle, and a state reference.
=cut

sub handle_request {
    my ( $self, $rabbit_mq_channel, $reply_to, $body, $default_input_validators, $state ) = @_;

    my $res = $self->_validate_schema($body);
    if (!defined $res) {
	$self->_return_error($rabbit_mq_channel, $reply_to);
	return;
    }

    $res = $self->_parse_input_parameters( decode_json($body), $default_input_validators);

    if (!defined $res) {
        $self->_return_error($rabbit_mq_channel, $reply_to);
        return;
    }

    #--- call the callback
    my $callback    = $self->{'callback'};

    $self->{'success_callback'} = sub { 
        my $results = shift; 
        $self->_return_results($rabbit_mq_channel, $reply_to, $results); 
    };

    $self->{'error_callback'} = sub {
        my $results = shift;
        $self->_return_error($rabbit_mq_channel, $reply_to, $results);
    };

    if($self->{'async'}){
	
	my $results = &$callback($self,dclone($self->{'input_params'}),$state);
	return 1;

    }else{
	my $results     = &$callback($self,$self->{'input_params'},$state);
	
	if (!defined $results) {
	    my $error_callback = $self->{'error_callback'};
	    &$error_callback();
	    return;
	}
	else {
	    #--- return results
	    my $success_callback = $self->{'success_callback'};
	    &$success_callback( $results );
	    return 1;
	}
    }
}

1;

