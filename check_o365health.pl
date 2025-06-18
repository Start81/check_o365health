#!/usr/bin/perl -w
#===============================================================================
# Script Name   : check_o365health.pl
# Usage Syntax  : check_o365health [-v] -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> [-N <SERVICENAME>] 
# Author        : DESMAREST JULIEN (Start81)
# Version       : 1.0.1
# Last Modified : 18/06/2025
# Modified By   : DESMAREST JULIEN (Start81)
# Description   : check o365 service health
# Depends On    : REST::Client, Data::Dumper,  Monitoring::Plugin, File::Basename, JSON, Readonly, URI::Encode
#
# Changelog:
#    Legend:
#       [*] Informational, [!] Bugix, [+] Added, [-] Removed
# - 17/06/2025 | 1.0.0 | [*] initial realease
# - 18/06/2025 | 1.0.1 | [*] some optimization
#===============================================================================
use REST::Client;
use Data::Dumper;
use JSON;
use utf8;
use File::Basename;
use strict;
use warnings;
use Readonly;
use Monitoring::Plugin;
use URI::Encode;
Readonly our $VERSION => '1.0.1';
my $graph_endpoint = "https://graph.microsoft.com";
my @services_name = ();
my @criticals = ();
my @warnings = ();
my @unknown = ();
my @ok = ();

my $o_verb;
#https://learn.microsoft.com/fr-fr/graph/api/resources/servicehealthissue?view=graph-rest-1.0#servicehealthstatus-values
my %state  =("serviceOperational"=>0, 
"investigating"=>1,
"restoringService"=>1, 
"verifyingService"=>0, 
"serviceRestored"=>0, 
"postIncidentReviewPublished"=>0, 
"serviceDegradation"=>1, 
"serviceInterruption"=>2, 
"extendedRecovery"=>1, 
"falsePositive"=>0, 
"investigationSuspended"=>1,
# 	Reserved for future use.
"resolved"=>3,
"mitigatedExternal"=>3,
"mitigated"=>3,
"resolvedExternal"=>3,
"confirmed"=>3,
"reported"=>3
);

sub verb { my ($t,$lvl)=@_; print $t,"\n" if ($o_verb and ($o_verb>=$lvl)) ; return 0}
my $me = basename($0);
my $client = REST::Client->new();
my $np = Monitoring::Plugin->new(
    usage => "Usage: %s  [-v] -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> [-N <SERVICENAME>]   \n ",
    plugin => $me,
    shortname => " ",
    blurb => "$me check o365 service health",
    version => $VERSION,
    timeout => 30
);

#write content in a file
sub write_file {
    my ($content,$tmp_file_name) = @_;
    my $fd;
    verb("write $tmp_file_name",3);
    if (open($fd, '>', $tmp_file_name)) {
        print $fd $content;
        close($fd);       
    } else {
        my $msg ="unable to write file $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    
    return 0
}

#Read previous token  
sub read_token_file {
    my ($tmp_file_name) = @_;
    my $fd;
    my $token ="";
    my $last_mod_time;
    verb("read $tmp_file_name",4);
    if (open($fd, '<', $tmp_file_name)) {
        while (my $row = <$fd>) {
            chomp $row;
            $token=$token . $row;
        }
        $last_mod_time = (stat($fd))[9];
        close($fd);
    } else {
        my $msg ="unable to read $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return ($token,$last_mod_time)
    
}

#get a new acces token
sub get_access_token{
    my ($clientid,$clientsecret,$tenantid) = @_;
    verb(" tenantid = " . $tenantid,3);
    verb(" clientid = " . $clientid,3);
    verb(" clientsecret = " . $clientsecret,3);
    my $uri = URI::Encode->new({encode_reserved => 1});
    my $encoded_graph_endpoint = $uri->encode($graph_endpoint . '/.default');
    verb("$encoded_graph_endpoint",3);
    my $payload = 'grant_type=client_credentials&client_id=' . $clientid . '&client_secret=' . $clientsecret . '&scope='.$encoded_graph_endpoint;
    my $url = "https://login.microsoftonline.com/" . $tenantid . "/oauth2/v2.0/token";
    $client->POST($url,$payload);
    if ($client->responseCode() ne '200') {
        my $msg = "response code : " . $client->responseCode() . " Message : Error when getting token" . $client->{_res}->decoded_content;
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return $client->{_res}->decoded_content;
};

$np->add_arg(
    spec => 'tenant|T=s',
    help => "-T, --tenant=STRING\n"
          . '   The GUID of the tenant to be checked',
    required => 1
);
$np->add_arg(
    spec => 'clientid|I=s',
    help => "-I, --clientid=STRING\n"
          . '   The GUID of the registered application',
    required => 1
);
$np->add_arg(
    spec => 'clientsecret|p=s',
    help => "-p, --clientsecret=STRING\n"
          . '   Access Key of registered application',
    required => 1
);
$np->add_arg(
    spec => 'servicename|N=s', 
    help => "-N, --servicename=STRING\n"  
         . '   name of the service to check let this empty to get all service health',
    required => 0
);

$np->getopts;
my $msg = "";
my $tenantid = $np->opts->tenant;
my $clientid = $np->opts->clientid;
my $clientsecret = $np->opts->clientsecret; 
my $o_service_name = $np->opts->servicename;
$o_verb = $np->opts->verbose if (defined $np->opts->verbose);
my $i = 0;
verb(" tenantid = " . $tenantid,1);
verb(" clientid = " . $clientid,1);
verb(" clientsecret = " . $clientsecret,1);
#Get token
my $tmp_file = "/tmp/$clientid.tmp";
my $token;
my $last_mod_time;
my $token_json;
if (-e $tmp_file) {
    #Read previous token
    ($token,$last_mod_time) = read_token_file ($tmp_file);
    $token_json = from_json($token);
    #check token expiration
    my $expiration =  $last_mod_time + ($token_json->{'expires_in'} - 60);
    my $current_time = time();
    verb ("current_time : $current_time   exptime : $expiration",4);
    if ($current_time > $expiration ) {
        #If token is too old
        #get a new token
        $token = get_access_token($clientid,$clientsecret,$tenantid);
	eval {
	    $token_json = from_json($token);
	} or do {
	    $np->plugin_exit('UNKNOWN',"Failed to decode JSON: $@");
	};
        write_file($token,$tmp_file);
    }
} else {
    #First token
    $token = get_access_token($clientid,$clientsecret,$tenantid);
    eval {
	$token_json = from_json($token);
    } or do {
        $np->plugin_exit('UNKNOWN',"Failed to decode JSON: $@");
    };
    write_file($token,$tmp_file);
}
verb(Dumper($token_json ),4);
$token = $token_json->{'access_token'};
$client->addHeader('Authorization', 'Bearer ' . $token);
$client->addHeader('Content-Type', 'application/x-www-form-urlencoded');
$client->addHeader('Accept', 'application/json');
my $url = "$graph_endpoint/v1.0/admin/serviceAnnouncement/healthOverviews";
$url = "$graph_endpoint/v1.0/admin/serviceAnnouncement/healthOverviews/$o_service_name/" if ($o_service_name) ;

verb($url,1);
$client->GET($url);
if($client->responseCode() ne '200'){
    $msg ="response code : " . $client->responseCode() . " Message : Error when getting serviceAnnouncement " .  $client->responseContent();
    $np->plugin_exit('UNKNOWN',$msg);
}
my $health_overviews_list = from_json($client->responseContent());
verb(Dumper($health_overviews_list),3);

$i = 0;
my $status='';
my $service='';
if ($o_service_name) {
    $status=$health_overviews_list->{'status'};
    $service=$health_overviews_list->{'service'};
    verb("Service Name : $service",1);
    push( @criticals, "Service : $service state is $status") if ($state{$status} == 2);
    push( @warnings, "Service : $service state is $status") if ($state{$status} == 1);
    push( @unknown, "Service : $service state is $status") if ($state{$status} == 3);
    push( @ok,"Service : $service is $status (OK)") if ( $state{$status} == 0);
} else {
    verb("Loop on service",1);
    do {
        $status=$health_overviews_list->{'value'}->[$i]->{'status'};
        $service=$health_overviews_list->{'value'}->[$i]->{'service'};
        verb($service,1);
        push( @criticals, "Service : $service state is $status") if ($state{$status} == 2);
        push( @warnings, "Service : $service state is $status") if ($state{$status} == 1);
        push( @unknown, "Service : $service state is $status") if ($state{$status} == 3);
        push (@ok,"Service : $service is $status (OK)") if ( $state{$status} == 0);
        $i++;
    } while (exists $health_overviews_list->{'value'}->[$i]);
}
$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('UNKNOWN', join(', ', @unknown)) if (scalar @unknown > 0);
$np->plugin_exit('OK', join(', ', @ok));
