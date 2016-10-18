#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;

my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
    queue => "Test",
    exchange => "Test",
    topic => "Test.Data",
    user => "guest",
    pass => "guest",
    port => "5672"
    );

my $method = GRNOC::RabbitMQ::Method->new(
    name => "get",
    description => "get data from queue",
    callback => \&get,
    );
$dispatcher->register_method($method);

$method = GRNOC::RabbitMQ::Method->new(
    name => "plus",
    description => "adds two numbers",
    callback => \&plus);
$method->add_input_parameter(
    name => 'a',
    description => "first addend",
    pattern => '^(-?[0-9]+)$' );
$method->add_input_parameter(
    name => 'b',
    description => "second addend",
    pattern => '^(-?[0-9]+)$' );
$dispatcher->register_method($method);

$dispatcher->start_consuming();

sub plus {
    my ($method_obj,$params,$state) = @_;
    my $a = $params->{'a'}{'value'};
    my $b = $params->{'b'}{'value'};
    return { result => ($a+$b) };
}

sub get {
    return {success => 1};
}
