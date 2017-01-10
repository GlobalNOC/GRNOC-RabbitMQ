#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 11;

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
    callback => sub { my $mref = shift; my $pref = shift; 
                      return $pref->{'a'}{'value'} + $pref->{'b'}{'value'}});

ok(!$method->set_schema_validator(), "Failed to set Schema without specifying schema");


ok($method->set_schema_validator( schema => { type => 'object',
                                           properties => { a => { type => 'number', required => 1},
                                                           b => { type => 'number', required => 1}}}));


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

ok(defined($res->{'error'}) && $res->{'error'} == 1, "Error was defined");
ok($res->{'error_text'} eq 'JSON did not validate against the specified Schema because: $.b string value found, but a number is required', "Proper error text was returned");


$client->plus( a => 5,
               b => 6,
               c => 'foobar',
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok($res->{'results'} == 11, "No AdditionalProperties bit set allowed extra params");
ok(!defined($res->{'error'}), "No Error defined");

$client->plus( a => 5,
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok(defined($res->{'error'}) && $res->{'error'} == 1, "Error was defined");
ok($res->{'error_text'} eq 'JSON did not validate against the specified Schema because: $.b is missing and it is required', "Proper error text was returned");

$method->set_schema_validator( schema => { type => 'object',
                                           additionalProperties => 0,
                                           properties => { a => { type => 'number', required => 1},
                                                           b => { type => 'number', required => 1}}});

$client->plus( a => 5,
               b => 6,
               c => 'foobar',
               async_callback => sub {
                   $res = shift;
                   $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok(defined($res->{'error'}) && $res->{'error'} == 1, "Error was defined");
ok($res->{'error_text'} eq 'JSON did not validate against the specified Schema because: $ The property c is not defined in the schema and the schema does not allow additional properties', "failes when we specify the additional properties");
