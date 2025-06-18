## check_o365health

check o365 service health

### prerequisites

This script uses theses libs : 
REST::Client, Data::Dumper,  Monitoring::Plugin, File::Basename, JSON, Readonly, URI::Encode

to install them type :

```
(sudo) cpan REST::Client Data::Dumper JSON Readonly Monitoring::Plugin File::Basename URI::Encode
```

This script writes the authentication information in the /tmp directory it will be necessary to verify that this directory exists and that the account which will launch the script has the necessary access permissions.

this script use an azure app registration  azure with access permissions on  graph api : type application,  ServiceHealth.Read.All.

### Use case

```bash
check_o365health.pl 1.0.1

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

check_o365health.pl check o365 service health

Usage: check_o365health.pl  [-v] -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> [-N <SERVICENAME>]


 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -T, --tenant=STRING
   The GUID of the tenant to be checked
 -I, --clientid=STRING
   The GUID of the registered application
 -p, --clientsecret=STRING
   Access Key of registered application
 -N, --servicename=STRING
   name of the service to check let this empty to get all service health
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 30)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```

sample : 

```bash
perl check_o365health.pl -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> -N  "Microsoft Entra"
```

you may get :

```bash
OK - Service : Microsoft Entra is serviceOperational (OK)
```
