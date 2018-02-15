#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 7;

use GRNOC::Log;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;

GRNOC::Log->new( level => 'ERROR');


#create the dispatcher
my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );

my $method = GRNOC::RabbitMQ::Method->new(
    name => "plus",
    description => "adds two numbers",
    callback => sub { my $mref = shift; my $pref = shift; return $pref->{'a'}{'value'} + $pref->{'b'}{'value'}});

$method->add_input_parameter(
    name => 'a',
    description => "first addend",
    pattern => '^(-?[0-9]+)$' );

$method->add_input_parameter(
    name => 'b',
    description => "second addend",
    pattern => '^(-?[0-9]+)$' );
$dispatcher->register_method($method);

my $client = GRNOC::RabbitMQ::Client->new(
    topic => "Test.Data",
    exchange => "Test",
    user => "guest",
    pass => "guest"
    );

my $res;
$client->plus( a => 5,
               b => 6,
               async_callback => sub { 
                   $res = shift;  
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok($res->{'results'} == 11);

$client->plus( a => 5,
               b => 'b',
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok(defined($res->{'error'}), "Error was defined");
ok($res->{'error'} eq 'Test.Data.plus: CGI input parameter b does not match pattern /^(-?[0-9]+)$/ ', "Proper error text was returned");


$client->plus( a => 5,
               b => 6,
               c => 'foobar',
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok(defined($res->{'error'}), "Error was defined");
ok($res->{'error'} eq 'JSON did not validate against the specified Schema because: $ The property c is not defined in the schema and the schema does not allow additional properties', "Proper error text was retuned");

$client->plus( a => 5,
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok(defined($res->{'error'}), "Error was defined");
ok($res->{'error'} eq 'JSON did not validate against the specified Schema because: $.b is missing and it is required', "Proper error text was returned");
