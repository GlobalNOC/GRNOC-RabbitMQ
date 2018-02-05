#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Test::More tests => 32;

use GRNOC::Log;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use GRNOC::WebService::Regex;

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

$method = GRNOC::RabbitMQ::Method->new( name => "test",
                                        description => "foo",
                                        callback => sub { my $m_ref = shift; my $p_ref = shift; return $p_ref; });

$method->add_input_parameter( name => 'foo',
                              description => "first addend",
                              schema => {'type' => 'array',
                                         'items' => {'type' => 'string'},
                                         'minItems' => 1});

$dispatcher->register_method( $method );

$client->test( foo => [ "foo","bar" ], async_callback => sub { $res = shift;
                                                               $dispatcher->stop_consuming();
               });

$dispatcher->start_consuming();

ok($res->{'results'}{'foo'}{'value'}[0] eq 'foo' && $res->{'results'}{'foo'}{'value'}[1] eq 'bar', "Proper parameter results");

$method = GRNOC::RabbitMQ::Method->new( name => "regexp_tests",
                                        description => "testing regexps",
                                        callback => sub { 
                                            my $m_ref = shift; 
                                            my $p_ref = shift; 
                                            return $p_ref;
                                        });

$dispatcher->register_method($method);

$method->add_input_parameter( name => "bool",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::BOOLEAN,
                              description => "Foo");


$method->add_input_parameter( name => "float",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::FLOAT,
                              description => "Foo");

$method->add_input_parameter( name => "int",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::INTEGER,
                              description => "Foo");

$method->add_input_parameter( name => "num",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::ANY_NUMBER,
                              description => "Foo");

$method->add_input_parameter( name => "name",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::NAME_ID,
                              description => "Foo");

$method->add_input_parameter( name => "text",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::TEXT,
                              description => "Foo");

$method->add_input_parameter( name => "ip",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::IP_ADDRESS,
                              description => "Foo");

$method->add_input_parameter( name => "hostname",
                              required => 0,
                              pattern => $GRNOC::WebService::Regex::HOSTNAME,
                              description => "Foo");


$client->regexp_tests( async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                       });

$dispatcher->start_consuming();

ok(!defined($res->{'results'}{'bool'}{'value'}), "!defined bool value");
ok(!defined($res->{'results'}{'float'}{'value'}), "!defined float value");
ok(!defined($res->{'results'}{'int'}{'value'}), "!defined int value");
ok(!defined($res->{'results'}{'num,'}{'value'}), "!defined numbers value");
ok(!defined($res->{'results'}{'name'}{'value'}), "!defined name value");
ok(!defined($res->{'results'}{'text'}{'value'}), "!defined text value");
ok(!defined($res->{'results'}{'ip'}{'value'}), "!defined ip value");
ok(!defined($res->{'results'}{'hostname'}{'value'}), "!defined hostname value");

$client->regexp_tests( bool => 1,
                                  float => 1.02,
                                  int => 100,
                                  num => 10000000,
                                  name => 'foobar',
                                  text => ' multi line string that is longer than a name',
                                  ip => '10.0.0.0',
                                  hostname => 'test.grnoc.iu.edu',
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();

ok($res->{'results'}{'bool'}{'value'} == 1, "proper bool value");
ok($res->{'results'}{'float'}{'value'} == 1.02, "proper float value");
ok($res->{'results'}{'int'}{'value'} == 100, "proper int value");
ok($res->{'results'}{'num'}{'value'} == 10000000, "proper numbers value '" . $res->{'results'}{'num'}{'value'} . "'");
ok($res->{'results'}{'name'}{'value'} eq 'foobar', "proper name value");
ok($res->{'results'}{'text'}{'value'} eq 'multi line string that is longer than a name', "proper text value");
ok($res->{'results'}{'ip'}{'value'} eq '10.0.0.0', "proper ip value");
ok($res->{'results'}{'hostname'}{'value'} eq 'test.grnoc.iu.edu', "proper hostname value");

$client->regexp_tests( bool => 2,
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();

ok($res->{'error'}, "expected an error with invalid bool");
ok($res->{'error'} eq 'Test.Data.regexp_tests: Parameter bool only accepts either 0 or 1 for false or true values, respectively.', "Proper error text");

$client->regexp_tests( float => 'foo',
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();

ok($res->{'error'}, "expected an error with invalid float");
ok($res->{'error'} eq 'Test.Data.regexp_tests: Parameter float only accepts floating point numbers.', "Proper error text");

$client->regexp_tests( int => 1.02,
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();

ok($res->{'error'}, "expected an error with invalid int");
ok($res->{'error'} eq 'Test.Data.regexp_tests: Parameter int only accepts integer numbers.', "Proper error text");

$client->regexp_tests( num => 'asdf',
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();

ok($res->{'error'}, "expected an error with invalid number");
ok($res->{'error'} eq "Test.Data.regexp_tests: Parameter num only accepts numbers.");

$client->regexp_tests( name => "asdf" . 0x95,
                                  async_callback => sub { $res = shift;
                                               $dispatcher->stop_consuming();
                               });

$dispatcher->start_consuming();
