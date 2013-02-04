package require critcl 3

namespace eval ::fcgi {
}

critcl::license {Jos Decoster} {LGPLv3 / BSD}
critcl::summary {A Tcl wrapper for libfcgi}
critcl::description {
    fcgi is a Tcl binding for libfcgi (http://www.fastcgi.com/)
}
critcl::subject fcgi fasgcgi cgi

critcl::meta origin https://github.com/jdc8/tclfcgi

critcl::userconfig define mode {choose mode of libfcgi to build and link against.} {static dynamic}

if {[string match "win32*" [::critcl::targetplatform]]} {
    critcl::clibraries -llibfcgi -luuid -lws2_32 -lcomctl32 -lrpcrt4
    switch -exact -- [critcl::userconfig query mode] {
	static {
	    critcl::cflags /DDLL_EXPORT
	}
	dynamic {
	}
    }
} else {
    switch -exact -- [critcl::userconfig query mode] {
	static {
	    critcl::clibraries -l:libfcgi.a -lstdc++
	}
	dynamic {
	    critcl::clibraries -lfcgi
	}
    }

    critcl::clibraries -lpthread -lm

    if {[string match "macosx*" [::critcl::targetplatform]]} {
	critcl::clibraries -lgcc_eh
    } else {
	critcl::clibraries -lrt -luuid
    }
}
#critcl::cflags -ansi -pedantic -Wall


# Get local build configuration
if {[file exists "[file dirname [info script]]/fcgi_config.tcl"]} {
    set fd [open "[file dirname [info script]]/fcgi_config.tcl"]
    eval [read $fd]
    close $fd
}

critcl::tcl 8.5

critcl::ccode {
#include "errno.h"
#include "string.h"
#include "stdio.h"
#include "fcgiapp.h"

    typedef struct {
	Tcl_HashTable* requests;
	int id;
    } FCGXClientData;

    static Tcl_Obj* unique_namespace_name(Tcl_Interp* ip, FCGXClientData* cd) {
	Tcl_Eval(ip, "namespace current");
	Tcl_Obj* fqn = Tcl_GetObjResult(ip);
	fqn = Tcl_DuplicateObj(fqn);
	Tcl_IncrRefCount(fqn);
	if (!Tcl_StringMatch(Tcl_GetStringFromObj(fqn, 0), "::")) {
	    Tcl_AppendToObj(fqn, "::", -1);
	}
	Tcl_AppendToObj(fqn, "fcgi", -1);
	Tcl_AppendPrintfToObj(fqn, "%d", cd->id);
	cd->id = cd->id + 1;
	return fqn;
    }

    static FCGX_Request* known_request(Tcl_Interp* ip, FCGXClientData* cd, Tcl_Obj* obj)
    {
	Tcl_HashEntry* hashEntry = Tcl_FindHashEntry(cd->requests, Tcl_GetStringFromObj(obj, 0));
	if (!hashEntry) {
	    Tcl_Obj* err = Tcl_NewObj();
	    Tcl_AppendToObj(err, "request \"", -1);
	    Tcl_AppendObjToObj(err, obj);
	    Tcl_AppendToObj(err, "\" does not exists", -1);
	    Tcl_SetObjResult(ip, err);
	    return 0;
	}
	return (FCGX_Request*)Tcl_GetHashValue(hashEntry);
    }
}

critcl::ccommand ::fcgi::Init {cd ip objc objv} {
    if (FCGX_Init()) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("FCGX_Init failed", -1));
	return TCL_ERROR;
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::OpenSocket {cd ip objc objv} {
    if (objc != 3) {
	Tcl_WrongNumArgs(ip, 1, objv, "path backlog");
	return TCL_ERROR;
    }
    const char* path = Tcl_GetStringFromObj(objv[1], 0);
    int backlog = 0;
    if (Tcl_GetIntFromObj(ip, objv[2], &backlog) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong backlog argument, expected integer", -1));
	return TCL_ERROR;
    }
    int rt = FCGX_OpenSocket(path, backlog);
    if (rt < 0) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("FCGX_OpenSocket failed", -1));
	return TCL_ERROR;
    }
    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::CloseSocket {cd ip objc objv} {
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "socket");
	return TCL_ERROR;
    }
    int socket = 0;
    if (Tcl_GetIntFromObj(ip, objv[1], &socket) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong socket argument, expected integer", -1));
	return TCL_ERROR;
    }
    int rt = close(socket);
    if (rt) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("close failed", -1));
	return TCL_ERROR;
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::InitRequest {cd ip objc objv} {
    if (objc != 3) {
	Tcl_WrongNumArgs(ip, 1, objv, "socket flags");
	return TCL_ERROR;
    }
    int socket = 0;
    if (Tcl_GetIntFromObj(ip, objv[1], &socket) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong socket argument, expected integer", -1));
	return TCL_ERROR;
    }
    int flags = 0;
    /* TBD: Read flags */
    FCGX_Request* request = (FCGX_Request*)ckalloc(sizeof(FCGX_Request));
    int rt = FCGX_InitRequest(request, socket, flags);
    if (rt) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("FCGX_InitRequest failed", -1));
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    Tcl_Obj* fqn = unique_namespace_name(ip, ccd);
    int newPtr = 0;
    Tcl_HashEntry* hashEntry = Tcl_CreateHashEntry(ccd->requests, Tcl_GetStringFromObj(fqn, 0), &newPtr);
    Tcl_SetHashValue(hashEntry, request);
    Tcl_SetObjResult(ip, fqn);
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::Free {cd ip objc objv} {
    if (objc != 3) {
	Tcl_WrongNumArgs(ip, 1, objv, "request close");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    int do_close = 0;
    if (Tcl_GetBooleanFromObj(ip, objv[2], &do_close) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong close argument, expected boolean", -1));
	return TCL_ERROR;
    }
    FCGX_Free(request, do_close);
    ckfree((void*)request);
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::Accept_r {cd ip objc objv} {
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "request");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    int rt = FCGX_Accept_r(request);
    if (rt) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("FCGX_Accepr_r failed", -1));
	return TCL_ERROR;
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::Finish_r {cd ip objc objv} {
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "request");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    FCGX_Finish_r(request);
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::GetParam {cd ip objc objv} {
    if (objc < 2 || objc > 3) {
	Tcl_WrongNumArgs(ip, 1, objv, "request ?name?");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    if (objc == 3) {
	const char* value = FCGX_GetParam(Tcl_GetStringFromObj(objv[2], 0), request->envp);
	Tcl_Obj* d = Tcl_NewDictObj();
	Tcl_DictObjPut(ip, d, Tcl_NewStringObj("exists", -1), Tcl_NewIntObj(value != 0));
	if (value)
	    Tcl_DictObjPut(ip, d, Tcl_NewStringObj("value", -1), Tcl_NewStringObj(value, -1));
	Tcl_SetObjResult(ip, d);
    }
    else {
	Tcl_Obj* d = Tcl_NewDictObj();
	char** envp = request->envp;
	for (; *envp; ++envp) {
	    const char* idx = strchr(*envp, '=');
	    if (idx)
		Tcl_DictObjPut(ip, d, Tcl_NewStringObj(*envp, idx-(*envp)), Tcl_NewStringObj(idx+1, -1));
	}
	Tcl_SetObjResult(ip, d);
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::PutStr {cd ip objc objv} {
    if (objc != 4) {
	Tcl_WrongNumArgs(ip, 1, objv, "request stream string");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    const char* stream = Tcl_GetStringFromObj(objv[2], 0);
    int lstr = 0;
    const char* str = Tcl_GetStringFromObj(objv[3], &lstr);
    int rt = 0;
    if (strcmp(stream, "stdout") == 0)
	rt = FCGX_PutStr(str, lstr, request->out);
    else if (strcmp(stream, "stderr") == 0)
	rt = FCGX_PutStr(str, lstr, request->err);
    else {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Unknow stream specified", -1));
	return TCL_ERROR;
    }
    if (rt != lstr) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("FCGX_PutStr failed", -1));
	return TCL_ERROR;
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::GetStr {cd ip objc objv} {
    if (objc != 4) {
	Tcl_WrongNumArgs(ip, 1, objv, "request stream n");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    const char* stream = Tcl_GetStringFromObj(objv[2], 0);
    if (strcmp(stream, "stdin")) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Unknow stream specified", -1));
	return TCL_ERROR;
    }
    int n = 0;
    if (Tcl_GetIntFromObj(ip, objv[3], &n) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong n argument, expected integer", -1));
	return TCL_ERROR;
    }
    if (n > 0) {
	char* str = ckalloc(n);
	int rt = FCGX_GetStr(str, n, request->in);
	Tcl_SetObjResult(ip, Tcl_NewStringObj(str, rt));
	ckfree(str);
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::ccommand ::fcgi::SetExitStatus {cd ip objc objv} {
    if (objc != 4) {
	Tcl_WrongNumArgs(ip, 1, objv, "request stream status");
	return TCL_ERROR;
    }
    FCGXClientData* ccd = (FCGXClientData*)cd;
    FCGX_Request* request = known_request(ip, ccd, objv[1]);
    if (!request)
	return TCL_ERROR;
    const char* stream = Tcl_GetStringFromObj(objv[2], 0);
    int stat = 0;
    // TDB: get status as string
    if (Tcl_GetIntFromObj(ip, objv[3], &stat) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong status argument, expected integer", -1));
	return TCL_ERROR;
    }
    if (strcmp(stream, "stdout") == 0)
	FCGX_SetExitStatus(stat, request->out);
    else if (strcmp(stream, "stderr") == 0)
	FCGX_SetExitStatus(stat, request->err);
    else {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Unknow stream specified", -1));
	return TCL_ERROR;
    }
    return TCL_OK;
} -clientdata fcgxClientData

critcl::cinit {
    fcgxClientData = (FCGXClientData*)ckalloc(sizeof(FCGXClientData));
    fcgxClientData->requests = (struct Tcl_HashTable*)ckalloc(sizeof(struct Tcl_HashTable));
    Tcl_InitHashTable(fcgxClientData->requests, TCL_STRING_KEYS);
    fcgxClientData->id = 0;
} {
    static FCGXClientData* fcgxClientData = 0;
}

package provide fcgi 2.4.1
