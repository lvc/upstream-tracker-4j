#!/usr/bin/perl
##################################################################
# A script to manage daily runs of the Java API Tracker
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
#  Perl 5 (5.8 or newer)
#  Java API Tracker (1.2 or newer)
#  Java API Monitor (1.2 or newer)
#  Java API Compliance Checker (2.3 or newer)
#  PkgDiff (1.7.2 or newer)
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
use Fcntl qw(:flock SEEK_END);
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use Data::Dumper;

my $Testplan_Init = "scripts/testplan";

my $UpdateList = "scripts/update.info";
my $UpdateLock = "scripts/.update.lock";

my $TMP_DIR = tempdir(CLEANUP=>1);
my $Testplan = $TMP_DIR."/.testplan";
my $TestplanLock = $TMP_DIR."/.testplan.lock";
my $Date = getDate();
my $LogDir = "daily_log";
my %LogPath;

my $JREPORTS = "api-reports-4j/report";
my $SPONSORS_FILE = "sponsors.json";

my %Opt;

GetOptions(
    "timing!" => \$Opt{"Timing"},
    "cores=s" => \$Opt{"Cores"},
    "json!" => \$Opt{"Json"},
    "regen-dump!" => \$Opt{"RegenDump"},
    "rss!" => \$Opt{"Rss"},
    "sponsors!" => \$Opt{"Sponsors"},
    "all!" => \$Opt{"All"},
    "refresh-index!" => \$Opt{"RefreshIndex"},
    "refresh-reports!" => \$Opt{"RefreshReports"},
    "refresh-dumps!" => \$Opt{"RefreshDumps"},
    "compress!" => \$Opt{"Compress"},
    "clean-unused!" => \$Opt{"CleanUnused"},
    "library=s" => \$Opt{"TargetLibrary"},
    "disable-cache!" => \$Opt{"DisableCache"},
    "debug!" => \$Opt{"Debug"}
) or exit(1);

sub getDate()
{
    my ($Sec, $Min, $Hour, $Mday, $Mon, $Year, $Wday, $Yday, $Isdst) = localtime(time);
    
    return (1900+$Year)."-".fNum($Mon+1)."-".fNum($Mday);
}

sub fNum($)
{
    my $Num = $_[0];
    
    if(length($Num)==1) {
        return "0".$Num;
    }
    
    return $Num;
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    
    my $Dir = dirname($Path);
    if(not -d $Dir) {
        mkpath($Dir);
    }
    
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    
    open(FILE, ">>", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    
    open(FILE, "<", $Path) || die ("can't open file \'$Path\': $!\n");
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    
    return $Content;
}

sub registerUpdate($)
{
    my $Library = $_[0];
    
    open(my $ULock, $UpdateLock) or die "Can't open updates lock: $!";
    flock($ULock, LOCK_EX) or die "Can't lock updates: $!\n";
    
    my $UpdateInfo = {};
    if(-f $UpdateList) {
        $UpdateInfo = eval(readFile($UpdateList));
    }
    $UpdateInfo->{"Updated"}{$Library} = 1;
    writeFile($UpdateList, Dumper($UpdateInfo));
    
    flock($ULock, LOCK_UN) or die "Can't unlock updates: $!\n";
    close($ULock);
}

sub runUpdate($$)
{
    my ($Library, $N) = @_;
    
    my $Log = $LogPath{$N};
    
    my $STime = time();
    
    appendFile($Log, uc($Library)."\n");
    
    my $MonOpts = "";
    if($Opt{"Debug"}) {
        $MonOpts = " -debug";
    }
    my $Output = `japi-monitor -get -build-new $MonOpts profile/$Library.json 2>&1 | tee -a $Log`;
    
    if($Output=~/Downloading/i) {
        registerUpdate($Library);
    }
    
    my $Opts = "";
    if($Opt{"RegenDump"}) {
        $Opts .= " -regen-dump";
    }
    if($Opt{"Rss"}) {
        $Opts .= " -rss";
    }
    if($Opt{"Sponsors"} and -f $SPONSORS_FILE) {
        $Opts .= " -sponsors ".$SPONSORS_FILE;
    }
    if($Opt{"DisableCache"}) {
        $Opts .= " -disable-cache";
    }
    
    system("japi-tracker -build $Opts profile/$Library.json >>$Log 2>&1");
    
    if(-d "graph/$Library") {
        system("japi-tracker -build $Opts -target graph profile/$Library.json >>$Log 2>&1");
    }
    
    if(defined $Opt{"Json"}) {
        system("japi-tracker -json-report $JREPORTS profile/$Library.json >>$Log 2>&1");
    }
    
    if(defined $Opt{"Timing"}) {
        appendFile($Log, "Time spent: ".showDelta(time() - $STime)."\n");
    }
}

sub cleanUnused($)
{
    my $Library = $_[0];
    
    print "Clean unused data of $Library\n";
    system("japi-tracker profile/$Library.json -clean-unused -force >/dev/null 2>&1");
}

sub compressData($)
{
    my $Library = $_[0];
    
    print "Compressing $Library\n";
    system("japi-tracker profile/$Library.json -rebuild -t compress >/dev/null 2>&1");
}

sub refreshDumps($)
{
    my $Library = $_[0];
    
    print "Refreshing $Library\n";
    system("japi-tracker profile/$Library.json -rebuild -t apidump >/dev/null 2>&1");
}

sub refreshReports($)
{
    my $Library = $_[0];
    
    print "Refreshing $Library\n";
    system("japi-tracker profile/$Library.json -rebuild -t apireport >/dev/null 2>&1");
}

sub refreshIndex($)
{
    my $Library = $_[0];
    
    print "Refreshing $Library\n";
    
    my $Opts = "";
    if($Opt{"Rss"}) {
        $Opts .= " -rss";
    }
    if($Opt{"Sponsors"} and -f $SPONSORS_FILE) {
        $Opts .= " -sponsors ".$SPONSORS_FILE;
    }
    if($Opt{"DisableCache"}) {
        $Opts .= " -disable-cache";
    }
    
    if(-d "graph/$Library") {
        system("japi-tracker -build $Opts -target graph profile/$Library.json >/dev/null 2>&1");
    }
    else {
        system("japi-tracker $Opts profile/$Library.json >/dev/null 2>&1");
    }
    
    if(defined $Opt{"Json"}) {
        system("japi-tracker -json-report $JREPORTS profile/$Library.json >/dev/null 2>&1");
    }
}

sub showDelta($)
{
    my $Delta = $_[0];
    
    if($Delta<60) {
        return $Delta."s";
    }
    
    return int($Delta/60)."m";
}

sub getLibs()
{
    open(my $TLock, $TestplanLock) or die "Can't open testplan lock: $!";
    flock($TLock, LOCK_EX) or die "Can't lock testplan: $!\n";
    
    my $Content = eval(readFile($Testplan));
    my @Libs = ();
    
    foreach my $L (sort keys(%{$Content}))
    {
        if(not $Content->{$L})
        {
            foreach my $LE (split(";", $L)) {
                push(@Libs, $LE);
            }
            $Content->{$L} = 1;
            
            last;
        }
    }
    
    writeFile($Testplan, Dumper($Content));
    
    flock($TLock, LOCK_UN) or die "Can't unlock testplan: $!\n";
    close($TLock);
    
    return @Libs;
}

sub getTotalCores()
{
    my $TotalCores = qx!grep -c -P '^processor\\s+:' /proc/cpuinfo!;
    chomp($TotalCores);
    return $TotalCores;
}

sub scenario()
{
    $Data::Dumper::Sortkeys = 1;
    
    if(not -d "scripts")
    {
        print STDERR "ERROR: can't find ./scripts directory\n";
        exit(1);
    }
    
    $Opt{"RegenDump"} = 1;
    
    if($Opt{"All"})
    {
        $Opt{"Json"} = 1;
        $Opt{"Rss"} = 1;
        $Opt{"Sponsors"} = 1;
    }
    
    my $TotalCores = getTotalCores();
    
    if(defined $Opt{"Cores"})
    {
        if($Opt{"Cores"}>$TotalCores) {
            print STDERR "WARNING: too many cores selected\n";
        }
        elsif($Opt{"Cores"}<=0)
        {
            print STDERR "ERROR: the number of cores should be a positive integer\n";
            exit(1);
        }
    }
    else {
        $Opt{"Cores"} = $TotalCores/2;
    }
    
    mkpath($LogDir);

    my $InitContent = readFile($Testplan_Init);
    $InitContent=~s/#.*\n//g;
    my @List = split(/\s*\n\s*/, $InitContent);
    
    if(my $Target = $Opt{"TargetLibrary"})
    {
        if($Target=~/\A[\w\-]+\Z/)
        {
            if(grep {$_ eq $Target} @List) {
                @List = ($Target);
            }
            else
            {
                print STDERR "ERROR: library $Target is not found in the test plan\n";
                exit(1);
            }
        }
        else
        {
            my @Res = ();
            foreach my $L (@List)
            {
                if($L=~/$Target/) {
                    push(@Res, $L);
                }
            }
            
            if(@Res) {
                @List = @Res;
            }
            else
            {
                print STDERR "ERROR: no libraries matching pattern $Target in the test plan\n";
                exit(1);
            }
        }
    }

    my %Hash = map {$_=>0} @List;
    writeFile($Testplan, Dumper(\%Hash));
    writeFile($TestplanLock, "This file is used to lock testplan");
    writeFile($UpdateLock, "This file is used to lock update list");
    
    if(-e $UpdateList) {
        unlink($UpdateList);
    }
    
    my $STime = time();
    my @Pids = ();
    
    foreach my $Cn (0 .. $Opt{"Cores"}-1)
    {
        $LogPath{$Cn} = $LogDir."/LOG-".$Date.".".$Cn;
        
        if(not $Opt{"RefreshIndex"} and not $Opt{"RefreshReports"} and not $Opt{"RefreshDumps"} and not $Opt{"Compress"} and not $Opt{"CleanUnused"}) {
            unlink($LogPath{$Cn});
        }
        
        my $Pid = fork();
        
        if($Pid)
        { # parent
            push(@Pids, $Pid);
            next;
        }
        else
        {
            while(my @Ls = getLibs())
            {
                foreach my $L (@Ls)
                {
                    if($Opt{"CleanUnused"}) {
                        cleanUnused($L);
                    }
                    elsif($Opt{"Compress"}) {
                        compressData($L);
                    }
                    elsif($Opt{"RefreshReports"}) {
                        refreshReports($L);
                    }
                    elsif($Opt{"RefreshDumps"}) {
                        refreshDumps($L);
                    }
                    elsif($Opt{"RefreshIndex"}) {
                        refreshIndex($L);
                    }
                    else {
                        runUpdate($L, $Cn);
                    }
                }
            }
            
            if(not $Opt{"RefreshIndex"} and not $Opt{"RefreshReports"} and not $Opt{"RefreshDumps"} and not $Opt{"Compress"} and not $Opt{"CleanUnused"})
            {
                if(defined $Opt{"Timing"}) {
                    appendFile($LogPath{$Cn}, "Done in: ".showDelta(time() - $STime)."\n");
                }
            }
            
            exit(0);
        }
    }
    
    foreach my $Pid (@Pids) {
        waitpid($Pid, 0);
    }
    
    unlink($Testplan);
    unlink($TestplanLock);
    unlink($UpdateLock);
    
    system("japi-tracker -global-index");
    
    exit(0);
}

scenario();
