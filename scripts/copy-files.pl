#!/usr/bin/perl
##################################################################
# A script to transfer reports of the Java API Tracker to hosting
#
# Copyright (C) 2015-2018 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux
#
# REQUIREMENTS
# ============
#  Perl 5
#  ssh
#  scp
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301 USA
##################################################################
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case", "permute");
use File::Basename qw(dirname basename);
use File::Temp qw(tempdir);
use Cwd qw(cwd);

my $Testplan_Init = "scripts/testplan";
my $UpdateList = "scripts/update.info";

my $HostAddr = undef;
my $HostDir = undef;

my $TMP_DIR = tempdir(CLEANUP=>1);
my $ORIG_DIR = cwd();
my $JREPORTS = "api-reports-4j/report";

my %Opt;

GetOptions(
    "fast!" => \$Opt{"Fast"}, # 3 times faster but 3 times more web traffic
    "json!" => \$Opt{"Json"},
    "index-only!" => \$Opt{"IndexOnly"},
    "renew!" => \$Opt{"Renew"}
) or exit(1);

my $Target = undef;
if(@ARGV) {
    $Target = $ARGV[0];
}

sub initHosting()
{
    my $HostInfo = readFile("scripts/host.conf");
    
    if($HostInfo=~/HOST_ADDR\s*\=\s*(.+)/) {
        $HostAddr = $1;
    }
    
    if($HostInfo=~/HOST_DIR\s*\=\s*(.+)/) {
        $HostDir = $1;
    }
    
    if(not $HostAddr or not $HostDir)
    {
        print STDERR "ERROR: please init HOST_ADDR and HOST_DIR in host.conf\n";
        exit(1);
    }
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path);
    
    open(FILE, "<", $Path) || die ("can't open file \'$Path\': $!\n");
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    
    return $Content;
}

sub sendPackage($)
{
    my $Pkg = $_[0];
    
    if(not $Pkg or $Pkg eq "." or $Pkg eq "/") {
        return;
    }
    
    my $Name = basename($Pkg);
    
    system("scp $Pkg $HostAddr:$HostDir");
    if($?) {
        print STDERR "ERROR: failed to send package\n";
    }
    
    system("ssh $HostAddr \"cd $HostDir && tar -xf $Name && rm -f $Name\"");
    if($?) {
        print STDERR "ERROR: failed to extract package\n";
    }
    
    return 1;
}

sub sendFiles(@)
{
    my @Files = @_;
    
    my ($Ext, $Opt) = ("txz", "cJf");
    if(defined $Opt{"Fast"}) {
        ($Ext, $Opt) = ("tgz", "czf");
    }
    
    my $Pkg = $TMP_DIR."/update.package.$Ext";
    system("tar -$Opt $Pkg ".join(" ", @Files)." --exclude='*.json'");
    
    sendPackage($Pkg);
    unlink($Pkg);
}

sub scenario()
{
    if(not -d "scripts")
    {
        print STDERR "ERROR: can't find ./scripts directory\n";
        exit(1);
    }
    
    initHosting();
    
    my @List_A = ();
    foreach my $L (split(/\s*\n\s*/, readFile($Testplan_Init)))
    {
        foreach my $LL (split(/;/, $L))
        {
            push(@List_A, $LL);
        }
    }
    
    my @List_F = ();
    
    if(defined $Target)
    {
        if(not grep {$_ eq $Target} @List_A) {
            print STDERR "WARNING: the library \'$Target\' is not presented in the testplan\n";
        }
        
        if(not -d "timeline/".$Target)
        {
            print STDERR "ERROR: there is no report for \'$Target\'\n";
            exit(1);
        }
        
        @List_F = ($Target);
    }
    elsif($Opt{"All"}) {
        @List_F = @List_A;
    }
    else
    {
        if(-e $UpdateList)
        {
            my $UpdateInfo = eval(readFile($UpdateList));
            
            if(not $UpdateInfo or not $UpdateInfo->{"Updated"})
            {
                print STDERR "ERROR: there are no updates to copy\n";
                exit(1);
            }
            
            @List_F = sort keys(%{$UpdateInfo->{"Updated"}});
        }
        else
        {
            print STDERR "ERROR: there are no updates to copy\n";
            exit(1);
        }
    }
    
    my @Other = ("index.html", "css");
    if(-d "js") {
        push(@Other, "js");
    }
    if(-d "images") {
        push(@Other, "images");
    }
    if(-d "logo") {
        push(@Other, "logo");
    }
    
    sendFiles(@Other);
    
    foreach my $L (@List_F)
    {
        if(defined $Target)
        {
            if($L ne $Target) {
                next;
            }
        }
        print "Copy $L\n";
        
        my @Files = ("timeline/$L");
        
        if(not $Opt{"IndexOnly"})
        {
            push(@Files, "archives_report/$L");
            push(@Files, "compat_report/$L");
            
            if(-d "package_diff/$L") {
                push(@Files, "package_diff/$L");
            }
            if(-d "changelog/$L") {
                push(@Files, "changelog/$L");
            }
            if(-d "graph/$L") {
                push(@Files, "graph/$L");
            }
            if(-d "rss/$L") {
                push(@Files, "rss/$L");
            }
        }
        
        if($Opt{"Renew"}) {
            system("ssh $HostAddr \"cd $HostDir && rm -fr ".join(" ", @Files)." \"");
        }
        
        sendFiles(@Files);
    }
    
    system("ssh $HostAddr \"cd $HostDir && sed -i -e \'s/index\.html//\' index.html\""); # && find compat_report -empty -type d -delete
    
    if(defined $Opt{"Json"})
    {
        chdir($JREPORTS);
        system("git diff --exit-code || git pull && git add . && git commit -m 'AUTO update of reports' && git push");
        chdir($ORIG_DIR);
    }
    
    exit(0);
}

scenario();
