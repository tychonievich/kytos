
import os, os.path, datetime, time, sys

for p in sys.argv[1:]:
    n=os.path.basename(p)
    start_ns = int(datetime.datetime.strptime(n[:15], '%Y%m%d-%H%M%S').timestamp())*(10**9) + int(n[16:25])
    try:
        end_ns = os.stat(p).st_mtime_ns
    except:
        end_ns = os.path.getmtime(p)*(10**9)
    print((end_ns - start_ns) / (10**9))
