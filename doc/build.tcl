package require doctools

set format html
if {[llength $argv]} {
    set format [lindex $argv 0]
}

set on [doctools::new on -format $format]
set f [open fcgi.$format w]
puts $f [$on format {[include fcgi.man]}]
close $f

$on destroy
