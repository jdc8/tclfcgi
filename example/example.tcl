package require fcgi

if {[llength $argv] != 1} {
    puts stderr "Usage: example.tcl <path_or_port>"
    exit
}

set sock [fcgi OpenSocket [lindex $argv 0] 1]
fcgi Init
set req [fcgi InitRequest $sock {}]

while {1} {
    puts "### Accepr_r #############################################################################"
    fcgi Accept_r $req
    puts $req
    puts "### GetParam #############################################################################"
    set pd [fcgi GetParam $req]
    dict for {k v} $pd {
	puts "$k=$v"
    }
    puts "### GetStr ###############################################################################"
    set content ""
    if {[dict exists $pd "CONTENT_LENGTH"] && [string is integer -strict [dict get $pd "CONTENT_LENGTH"]] && [dict get $pd "CONTENT_LENGTH"] > 0} {
	set content [fcgi GetStr $req stdin [dict get $pd "CONTENT_LENGTH"]]
	puts $content
    }
    puts "### PutStr ###############################################################################"
    set C "Status: 200 OK
Content-Type: text/html

<html>
<body>
<h1>FCGI CriTcl wrapper test</h1>
<h2>Parameters<h2>
<table>
"
    dict for {k v} $pd {
	append C "<tr><td>$k</td><td>$v</td></tr>\n"
    }
    append C "</table>
<h2>Body</h2>
<pre>"
    append C $content
    append C "</pre>\n</body>\n</html>\n"
    fcgi PutStr $req stdout $C
    puts "### Finish_r #############################################################################"
    fcgi SetExitStatus $req stdout 0
    fcgi Finish_r $req
}
