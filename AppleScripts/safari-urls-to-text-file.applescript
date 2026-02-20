-- Sla alle Safari-tabblad-URL's op naar 'Safari-URLs.txt' op het bureaublad
set outPath to (path to desktop folder as text) & "Safari-URLs.txt"

-- Verzamel URLs uit alle vensters en tabs
set urlList to {}
tell application "Safari"
	if (count of windows) > 0 then
		repeat with w in windows
			repeat with t in tabs of w
				try
					set u to URL of t
					if u is not missing value and u is not "" then
						if urlList does not contain u then set end of urlList to u
					end if
				end try
			end repeat
		end repeat
	end if
end tell

-- Schrijf naar bestand
set urlText to (my join(urlList, linefeed)) & linefeed
try
	set f to open for access file outPath with write permission
	set eof f to 0
	write urlText to f
	close access f
on error errMsg number errNum
	try
		close access file outPath
	end try
	error errMsg number errNum
end try

on join(L, delim)
	set {oldTIDs, AppleScript's text item delimiters} to {AppleScript's text item delimiters, delim}
	set joined to L as text
	set AppleScript's text item delimiters to oldTIDs
	return joined
end join
