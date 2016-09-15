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
Requires: perl-GRNOC-Log
Requires: perl-AnyEvent
Requires: perl-AnyEvent-RabbitMQ
Requires: perl-JSON-XS
Requires: perl-JSON-Schema
Requires: perl-autovivification
Requires: perl(Data::Dumper)

%description
The GRNOC::RabbitMQ collection is a set of perl modules which are used to
provide and interact with GRNOC RabbitMQ services.

%prep
%setup -q -n perl-GRNOC-RabbitMQ-%{version}

%build
%{__perl} Makefile.PL PREFIX="%{buildroot}%{_prefix}" INSTALLDIRS="vendor"
make

%install
rm -rf $RPM_BUILDR_ROOT
make pure_install

# clean up buildroot
find %{buildroot} -name .packlist -exec %{__rm} {} \;

%{_fixperms} $RPM_BUILD_ROOT/*

%check
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644, root, root, -)
%{perl_vendorlib}/GRNOC/RabbitMQ.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Dispatcher.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Method.pm
%{perl_vendorlib}/GRNOC/RabbitMQ/Client.pm
%doc %{_mandir}/man3/GRNOC::RabbitMQ.3pm.gz
%doc %{_mandir}/man3/GRNOC::RabbitMQ::Dispatcher.3pm.gz
%doc %{_mandir}/man3/GRNOC::RabbitMQ::Method.3pm.gz
%doc %{_mandir}/man3/GRNOC::RabbitMQ::Client.3pm.gz

%changelog

