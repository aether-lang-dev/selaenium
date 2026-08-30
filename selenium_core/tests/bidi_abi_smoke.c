// C smoke test: drive BiDi through the FLAT C ABI (what an FFI binding does).
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
int main(int argc, char** argv) {
    void* lib = dlopen(argv[1], RTLD_NOW);
    if (!lib) { fprintf(stderr,"dlopen: %s\n", dlerror()); return 2; }
    // driver + W3C session (to get webSocketUrl)
    void* (*launch)(const char*,int) = dlsym(lib,"aether_sel_embed_launch_driver");
    char* (*durl)(void*)            = dlsym(lib,"aether_sel_embed_driver_url");
    void  (*dstop)(void*)           = dlsym(lib,"aether_sel_embed_stop_driver");
    void* (*sopen)(const char*)     = dlsym(lib,"aether_sel_embed_open");
    int   (*sexec)(void*,const char*,const char*) = dlsym(lib,"aether_sel_embed_execute");
    char* (*sval)(void*)            = dlsym(lib,"aether_sel_embed_last_value");
    void  (*sclose)(void*)          = dlsym(lib,"aether_sel_embed_close");
    // BiDi ABI
    void* (*bopen)(const char*)     = dlsym(lib,"aether_sel_embed_bidi_open");
    int   (*bsend)(void*,int,const char*,const char*) = dlsym(lib,"aether_sel_embed_bidi_send");
    int   (*bpump)(void*,int)       = dlsym(lib,"aether_sel_embed_bidi_pump");
    char* (*bpollr)(void*,int)      = dlsym(lib,"aether_sel_embed_bidi_poll_reply");
    void  (*bclose)(void*)          = dlsym(lib,"aether_sel_embed_bidi_close");
    char* (*fstr)(char*)            = dlsym(lib,"aether_sel_embed_free_string");
    if(!bopen||!bsend||!bpump||!bpollr){fprintf(stderr,"bidi dlsym missing\n");return 2;}

    void* dh = launch(argv[2], 15000);
    if(!dh){fprintf(stderr,"driver launch null\n");return 1;}
    char* base = durl(dh);
    void* s = sopen(base);
    const char* caps = "{\"capabilities\":{\"alwaysMatch\":{\"webSocketUrl\":true,\"goog:chromeOptions\":{\"binary\":\"/home/paul/.cache/selenium/chrome/linux64/152.0.7977.64/chrome\",\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]}}}}";
    int rc = sexec(s,"newSession",caps);
    if(rc!=0){fprintf(stderr,"newSession rc=%d\n",rc);return 1;}
    char* v = sval(s);
    // crude extract of webSocketUrl
    char* p = strstr(v,"\"webSocketUrl\":\"");
    if(!p){fprintf(stderr,"no webSocketUrl in %s\n",v);return 1;}
    p += strlen("\"webSocketUrl\":\"");
    char ws[256]; int i=0; while(*p!='"'&&i<255){ws[i++]=*p++;} ws[i]=0;
    printf("webSocketUrl=%s\n", ws);

    void* b = bopen(ws);
    if(!b){fprintf(stderr,"bidi_open null\n");return 1;}
    // send two concurrent commands, pump, correlate by id
    bsend(b,10,"session.status","{}");
    bsend(b,11,"browsingContext.getTree","{}");
    char *r10=0,*r11=0; int waited=0;
    while(waited<10000){
        if(!r10){char*x=bpollr(b,10); if(x&&x[0]){r10=x;} else if(x) fstr(x);}
        if(!r11){char*x=bpollr(b,11); if(x&&x[0]){r11=x;} else if(x) fstr(x);}
        if(r10&&r11) break;
        bpump(b,50); waited+=50;
    }
    int ok10 = r10 && strstr(r10,"\"type\":\"success\"");
    int ok11 = r11 && strstr(r11,"context");
    printf("concurrent id10=%s id11=%s\n", ok10?"OK":"FAIL", ok11?"OK":"FAIL");
    bclose(b); sexec(s,"quit","{}"); sclose(s); dstop(dh);
    if(ok10&&ok11){printf("C-ABI BIDI SMOKE OK\n"); return 0;}
    return 1;
}
