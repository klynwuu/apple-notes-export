-- Optimized script to create a reminder from the selected Apple Note,
-- using NoteStore.sqlite to retrieve the real note identifier for the deep link.
-- The deep link is appended as a new line to the reminder’s body.

tell application "Notes"
	activate
	set selectedNotes to selection
	if selectedNotes is {} then
		display dialog "No note selected. Please select a note in Notes." buttons {"OK"} default button "OK"
		return
	end if
	
	set theNote to item 1 of selectedNotes
	-- Bring the note to a separate window so the user sees which note will be used
	show theNote with separately
	
	-- Use the note's title (its first row) as the reminder title
	set noteTitle to name of theNote
	
	-- Get the note’s full plain text content and extract its second line
	set noteContent to plaintext of theNote
	set noteParagraphs to paragraphs of noteContent
	if (count of noteParagraphs) ≥ 2 then
		set secondLine to item 2 of noteParagraphs
	else
		set secondLine to ""
	end if
	
	-- Extract the first 100 characters from the second line (or all if shorter)
	if (length of secondLine) > 100 then
		set shortContent to text 1 thru 100 of secondLine
	else
		set shortContent to secondLine
	end if
	
	-- Retrieve the note's unique identifier (a Core Data URL)
	set noteIdentifierURL to id of theNote
end tell

-- Process the noteIdentifierURL to extract the internal primary key (e.g. from "p2405")
set oldDelims to text item delimiters
set text item delimiters to "/"
set urlItems to text items of noteIdentifierURL
set text item delimiters to oldDelims
set lastItem to last item of urlItems
if (length of lastItem) > 1 then
	set internalPK to text 2 thru -1 of lastItem
else
	set internalPK to lastItem
end if

-- Query the NoteStore.sqlite database to get the real note identifier (UUID)
set sqliteQuery to "SELECT ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK=" & internalPK & ";"
try
	set realNoteID to do shell script "/usr/bin/sqlite3 ~/Library/Group\\ Containers/group.com.apple.notes/NoteStore.sqlite " & quoted form of sqliteQuery
on error errMsg number errNum
	display dialog "Error retrieving note identifier: " & errMsg
	return
end try

-- Build the deep link URL using the real note identifier
set deepLink to "notes://showNote?identifier=" & realNoteID
set deepLinkMobile to "mobilenotes://showNote?identifier=" & realNoteID

-- Append the deep link to the short content on a new line
set reminderBody to shortContent & linefeed & deepLink & linefeed & deepLinkMobile

-- Compute the coming Saturday at 10:00 AM
set currentDate to current date
set currentWeekday to weekday of currentDate
if currentWeekday is Saturday then
	set daysUntilSaturday to 7
else if currentWeekday is Sunday then
	set daysUntilSaturday to 6
else if currentWeekday is Monday then
	set daysUntilSaturday to 5
else if currentWeekday is Tuesday then
	set daysUntilSaturday to 4
else if currentWeekday is Wednesday then
	set daysUntilSaturday to 3
else if currentWeekday is Thursday then
	set daysUntilSaturday to 2
else if currentWeekday is Friday then
	set daysUntilSaturday to 1
end if
set remindDate to currentDate + (daysUntilSaturday * days)
set time of remindDate to (10 * hours)

-- Create the reminder in the Reminders app on the "Default" list
tell application "Reminders"
	activate
	set defaultList to first list whose name is "Default"
	tell defaultList
		make new reminder with properties {name:noteTitle, body:reminderBody, remind me date:remindDate}
	end tell
end tell
