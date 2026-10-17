#include "cpuhook.h"
#include <string.h>
static unsigned last_pc, wlo=1, whi=0, rlo=1, rhi=0;
#define NLOG 65536
static unsigned logb[NLOG][5]; static unsigned nlog;
static unsigned bp[16]; static unsigned nbp; static unsigned bphits[16];
static unsigned char wmap[65536];
unsigned char *retro_dbg_wmap(void){return wmap;}
static void hook(hook_type_t t, int w, unsigned a, unsigned v){
  if(t==HOOK_M68K_E){ last_pc=a; for(unsigned i=0;i<nbp;i++) if(bp[i]==a) bphits[i]++; return; }
  a &= 0xffffff;
  if(t==HOOK_M68K_W && a>=0xff0000){ for(int i=0;i<w;i++) wmap[(a+i)&0xffff]=1; }
  if(t==HOOK_M68K_W && a>=wlo && a<=whi && nlog<NLOG){ unsigned *l=logb[nlog++]; l[0]=last_pc;l[1]=a;l[2]=v;l[3]=w;l[4]=1;}
  if(t==HOOK_M68K_R && a>=rlo && a<=rhi && nlog<NLOG){ unsigned *l=logb[nlog++]; l[0]=last_pc;l[1]=a;l[2]=v;l[3]=w;l[4]=0;}
}
void retro_dbg_enable(int on){ set_cpu_hook(on?hook:0); }
void retro_dbg_watch(unsigned lo,unsigned hi){ wlo=lo; whi=hi; }
void retro_dbg_rwatch(unsigned lo,unsigned hi){ rlo=lo; rhi=hi; }
unsigned retro_dbg_nlog(void){ return nlog; }
unsigned *retro_dbg_log(void){ return &logb[0][0]; }
void retro_dbg_clear(void){ nlog=0; memset(bphits,0,sizeof bphits); }
void retro_dbg_bp(unsigned i, unsigned a){ bp[i]=a; if(i+1>nbp) nbp=i+1; }
unsigned *retro_dbg_bphits(void){ return bphits; }
