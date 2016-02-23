Summary: GRNOC RabbitMQ Perl Libraries
Name: perl-GRNOC-RabbitMQ
Version: 1.0.0
Release: 1
License: APL 2.0
Group: Network
URL: http://globalnoc.iu.edu
Source0: %{name}-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch:noarch

BuildRequires: perl
Requires: perl-Log-Log4perl, perl-AnyEvent, perl-AnyEvent-RabbitMQ


* Thu Dec  5 2013 AJ Ragusa <aragusa@grnoc.iu.edu> - OESS Perl Libs
- Initial build.
