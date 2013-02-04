package require fcgi

set sock [fcgi::OpenSocket :9999 1]
fcgi::Init
set req [fcgi::InitRequest $sock {}]

while {1} {
    puts "### Accepr_r #############################################################################"
    fcgi::Accept_r $req
    puts "req = $req"
    puts "### GetParam #############################################################################"
    puts [fcgi::GetParam $req]
    puts "### PutStr ###############################################################################"
    puts "### PutStr ###############################################################################"
    set C "Status: 200 OK
Content-Type: text/html

<html>
<body>
<h1>FCGI CriTcl wrapper test</h1>
<h2>Parameters<h2>
<table>
"
    set pd [fcgi::GetParam $req]
    dict for {k v} $pd {
	append C "<tr><td>$k</td><td>$v</td></tr>\n"
    }
    append C "</table>
<h2>Body</h2>
<pre>"
    if {[dict exists $pd "CONTENT_LENGTH"] && [string is integer -strict [dict get $pd "CONTENT_LENGTH"]] && [dict get $pd "CONTENT_LENGTH"] > 0} {
	append C [fcgi::GetStr $req stdin [dict get $pd "CONTENT_LENGTH"]]
    }
    append C "</pre>\n</body>\n</html>\n"
    fcgi::PutStr $req stdout $C
    puts "### Finish_r #############################################################################"
    fcgi::SetExitStatus $req stdout 0
    fcgi::Finish_r $req
}
