Upstream Tracker 4J 2.1
=======================

Upstream Tracker 4J — a project to monitor and verify backward compatibility of upstream API changes in Java libraries.

Web: https://abi-laboratory.pro/java/tracker/

Contents
--------

1. [ About           ](#about)
2. [ Requires        ](#requires)
3. [ Test Plan       ](#test-plan)
4. [ Daily Run       ](#daily-run)
5. [ Logs            ](#logs)
6. [ Publish Reports ](#publish-reports)
7. [ Add library     ](#add-library)

About
-----

JSON-format reports: https://github.com/lvc/api-reports-4j

The tool is developed by Andrey Ponomarenko: https://abi-laboratory.pro/

Requires
--------

* Perl 5
* Java API Tracker (1.2 or newer)
* Java API Monitor (1.2 or newer)
* Java API Compliance Checker (2.3 or newer)
* PkgDiff (1.7.2 or newer)

You can use the installer-4j to automatically download from github and install necessary tools: https://github.com/lvc/installer-4j

Test Plan
---------

The file `scripts/testplan` contains the list of libraries to be monitored. You can write several libraries in one line separated by semicolon if you want to handle these libraries one-by-one in the specific order on one CPU. Other libraries will be processed in parallel on different CPUs.

Daily Run
---------

This script is used to organize daily runs of the API Tracker and API Monitor tools:

    perl scripts/daily-run.pl -all

Logs
----

See logs in the `daily_log/` directory.

Publish Reports
---------------

You can copy reports to a hosting defined by `HOST_ADDR` and `HOST_DIR` variables in the `scripts/host.conf` file. The script will copy all necessary reports and styles (compressed as tar.gz) via scp to the hosting directory:

    perl scripts/copy-files.pl -fast [library]

Add library
-----------

Please report an issue if you'd like to add some library to the tracker: https://github.com/lvc/upstream-tracker-4j/issues

Enjoy!
