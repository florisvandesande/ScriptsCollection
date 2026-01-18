tell application "System Settings"
	activate
	reveal anchor "Widgets" of pane id "com.apple.Desktop-Settings.extension"
	
	repeat
		set currentPane to get current pane
		if currentPane is pane id "com.apple.Desktop-Settings.extension" then
			exit repeat
		else
			delay 1
		end if
	end repeat
end tell

delay 1

tell application "System Events"
	tell process "System Settings"
		set targetControl to checkbox "Toon Widgets" of group 6 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
		-- Check if the checkbox is not already checked (value of 0 means unchecked, 1 means checked)
		if value of targetControl is 1 then
			click targetControl
		end if
	end tell
end tell

tell application "System Settings" to quit