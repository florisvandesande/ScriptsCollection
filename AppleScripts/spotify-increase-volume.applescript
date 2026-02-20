tell application "Spotify"
	set currentvol to get sound volume
	-- volume wraps at 100 to 0
	if currentvol > 90 then
		set sound volume to 100
	else
		set sound volume to currentvol + 5
	end if
end tell