import sys
d=open(sys.argv[1],'rb').read()
ranges=[(int(a,16),int(b,16)) for a,b in (x.split('-') for x in sys.argv[2:])]
for a in range(0x20000,0x40000,2):
    op=(d[a]<<8)|d[a+1]
    tg=[]
    if op&0xF000==0x6000:
        disp=op&0xFF
        if disp==0: tg.append(a+2+int.from_bytes(d[a+2:a+4],'big',signed=True))
        elif disp!=0xFF: tg.append(a+2+(disp-256 if disp>127 else disp))
    if op in (0x4EBA,0x4EFA,0x41FA,0x43FA,0x45FA,0x47FA,0x49FA,0x4BFA): tg.append(a+2+int.from_bytes(d[a+2:a+4],'big',signed=True))
    if op&0xF0F8==0x50C8: tg.append(a+2+int.from_bytes(d[a+2:a+4],'big',signed=True))  # dbcc
    if op in (0x4EB9,0x4EF9): tg.append(int.from_bytes(d[a+2:a+6],'big'))
    for t in tg:
        for lo,hi in ranges:
            if lo<t<=hi: print('branch into %06X-%06X: from %06X to %06X'%(lo,hi,a,t))
