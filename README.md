# Kytos: a file submission helper for programing courses

Kytos (from the greek for an empty receptical) is a reasonable but not
paranoid sandboxing runner of for user-submitted code.

## Installing

You'll need to make sure you have

-   [`docker`](https://docker.io), typically in package managers as 
    `docker` or `docker.io`

-   [`inotifywait`](https://github.com/rvoicilas/inotify-tools), 
    typically in package managers as `inotify-tools`

-   [`jq`](https://stedolan.github.io/jq/), typically in package 
    managers as `jq`

-   Root access

Pick a location for the user-accessible parts of the project. You need
to have execute permissions on the directory for all user accounts who
will place code there (e.g., group `instructors` and user `www-data`
submissions come from apache scripts and shell access by instructors).
Do not create additional directoris there; this will be done by the
daemon script.

Ensure you have a docker image you want to use for running code. The
included `Dockerfile` and `setup_docker.sh` provide an example. You can
have separate images for individual assignments, but should generally 
create a default image as non-root users cannot create them.

### Customizing

In `sbw.sh` there are several customization points:

-   The line `DIR=/opt/sandbox-runner` sets up the directory where 
    users place code to be run and retrieve results; it may be changed 
    to any location you wish, but should not require shell escaping.

-   `DEF_TIMEOUT=10` and `DEF_IMAGE=sandbox_machine` define the default
    timout (in seconds) and docker image file to run. Note that jobs 
    are (currently) run sequentially, not in parallel, so timeouts 
    should not be made too large. `MAX_TIMEOUT=300` is provided to limit
    user-overridden timeouts from halting the system. 

You may also change other aspects of `sbw.sh` (subdirectory names and 
permissions, lockfile locations, etc.) if you wish.

### Daemon

The file `sbw.sh` is designed to be run once (forced with `flock`) by 
`root` in the background at all times. It has minimal outputs (those
created by `docker` and `inotifywait` primarily). Since it is not 
heavily tested, we advise adding a root crontab entry to periodically
restart it in case it crashes, such as

    # m h dom mon dow command
    17  *  *   *   *  nohup /bin/bash /path/to/sbw.sh &>/var/log/sbw.sh.log


## Using to run code

Once the daemon is running, users can submit jobs to it by

1. Pick a task path and a submission path. The task path will be used to
    locate command and support files; the submission path to locate
    uploads and test results.
    
    The following uses `$TP` to refer the task path and `$SP` to refer
    to the submission path; is also uses `$DIR` to refer to the main
    sandbox directory. For example, the following directories
    
     | Variable| Value                  |
     |:-------:|:-----------------------|
     | `$DIR`  | `/opt/sandbox-runner`  |
     | `$TP`   | `1110/pa01`            |
     | `$SP`   | `10am/mst3k`           |
     
    could give rise to the following directory tree
    
        /opt/sandbox-runner/
        ├── command/
        │   └── 1110/
        │       └── pa01.json
        ├── support
        │   └── 1110
        │       └── pa01
        │           └── test_pa01.py
        ├── runme/
        │   └── 1110/
        │       └── pa01/
        │           └── 10am/
        │               └── mst3k/
        │                   └── pa01.py
        ├── queue/
        │   └── 1110#pa01#10am#mst3k
        └── log/
            ├── .bad/
            │   └── 1110#pa01#10am#mst3k
            └── 1110/
                └── pa01/
                    └── 10am/
                        └── mst3k/
                            ├── 20180705-104056.689814717.err
                            ├── 20180705-104056.689814717.out
                            └── 20180705-104056.689814717.status



1. Create a command file in `$DIR/command/$TP.json` (note: the 
    extension-stripped name of this file is a directory name for
    submissions and logs).
    
    
    Command files are `json`-formatted and only have one required entry:
    `"command"` has an array (similar to `execv`) giving a command to
    run. For example
    
        {"command":["python3", "tester.py", "f1.txt", "f2.txt"]}
    
    will execute 
        
        python3 tester.py f1.txt f2.txt
    
    in docker for each queued submission directory.
    
    Optionally, you can also specify per-task information:
    
        {"command":["python3", "tester.py", "f1.txt", "f2.txt"]
        ,"timeout":30
        ,"network":true
        ,"image":"custom_docker_image_name"
        }
    
    Plase be sensitive to shared resources and do not enable networking
    or long timeouts unless they are necessary for the task at hand.

1. Optionally, create and upload to a support files directory 
    `$DIR/support/$TP/`. Any files placed here will be copied into each
    submission directory prior to running, replacing files of the same
    name (if any). Mode, ownership, and timestamps will be preserved
    in this copy using `cp -p`.

1. Create and upload to a submission directory `$DIR/runme/$TP/$SP/`.
    This will be the working directory for the submitted code too,
    and may contain additional directories if needed (as, e.g., for
    packages in java). The code will be run as a different user, so
    ensure the directory has any needed permissions (`chmod o+rx` at a
    minimum, plus `chmod o+w` if the program might create files).
    Hard links are OK (e.g., using `ln` instead of `cp`) but should not
    be writeable. Symlinks (e.g., using `ln -s` instead of `cp`) will
    almost certainly fail.
    
    You can create as many such directories as you want, even with
    different levels for different submissions,

1. Queue each submission for running by creating a file in
    `$DIR/queue/`. The contents of this file do not matter, but its
    name must be what you'd get from `echo "$TP/$SP" | tr '/' '#'`:
    that is, the path to the submission with `/` replaced by `#`.
    (note: this does mean no `#` are allowed in submission paths...).
    
    If the name of a file in `$DIR/queue/` does not match a submission
    directory or matches one without a command file, an error message
    will be placed in `$DIR/log/.bad/` with the same name as the queue
    file.

Once all of this is in place, the daemon will notice the queue entry,
execute the command in its docker image, and create three output files:

- `$DIR/log/$TP/$SP/datetime.out` has stdout for the executed program
- `$DIR/log/$TP/$SP/datetime.err` has stderr for the executed program
- `$DIR/log/$TP/$SP/datetime.status` has any status notes about execution

Datetimes are formatted as `date +%Y%m%d-%H%M%S.%N`. Approximate total
runtime (including docker overhead) can be found by comparing a filename
to it's stat date, as e.g., with the following Python script:

````python
import os, os.path, datetime, sys

for p in sys.argv[1:]:
    n=os.path.basename(p)
    start_ns = int(datetime.datetime.strptime(n[:15], '%Y%m%d-%H%M%S').timestamp())*(10**9) + int(n[16:25])
    try:
        end_ns = os.stat(p).st_mtime_ns
    except:
        end_ns = os.path.getmtime(p)*(10**9)
    print((end_ns - start_ns) / (10**9), 'seconds')
````

## FAQ

#### What if I want to provide input to the program?

Write a tester to do this for you and run the tester.  Experience with 
[archimedes](https://github.com/tychonievich/archimedes) taught us that
testers with input sometimes want to be quite nuanced, emulating a 
prompt-reply tty or the like, and that eager `stdin` readers in some
default runtimes make this less than obviously portable.

Consider using [`expect`](https://www.nist.gov/services-resources/software/expect)
or an implementation/clone  for your language (e.g., Python's 
standard library `pexepect` or
<https://github.com/ronniedong/Expect-for-Java>). Note this almost
always means having different processes running the code and pretending
to be the user, and evne then is more nuances than you might expect.

I do have a much simpler (and thus less featureful) `expect` tool on my
to-do list, but pretty far down.
