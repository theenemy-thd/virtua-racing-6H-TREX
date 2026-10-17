import sys, capstone
rom=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); n=int(sys.argv[3]) if len(sys.argv)>3 else 40
md=capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000)
while n>0:
    ins=next(md.disasm(rom[a:a+12], a, 1), None)
    if ins is None:
        print('%06X: %-22s dc.w'%(a, rom[a:a+2].hex())); a+=2
    else:
        print('%06X: %-22s %s %s'%(a, ins.bytes.hex(), ins.mnemonic, ins.op_str)); a+=ins.size
    n-=1
