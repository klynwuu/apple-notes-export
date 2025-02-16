on writeToFile(filename, filecontents)
	set theOutput to open for access file filename with write permission
	set eof of theOutput to 0
	-- If this is an HTML file, ensure a UTF-8 meta tag is present so Chinese characters display correctly.
	if filename ends with ".html" then
		if filecontents does not contain "<meta charset=" then
			-- If the exported content already has <html> tag, insert the meta tag inside <head>
			if filecontents contains "<html" then
				set filecontents to my insertMetaCharset(filecontents)
			else
				-- Otherwise, wrap the content in a standard HTML container with meta charset
				set filecontents to "<html><head><meta charset=\"UTF-8\"></head><body>" & filecontents & "</body></html>"
			end if
		end if
	end if
	-- Write the file contents as UTF-8 text
	write filecontents to theOutput as Çclass utf8È
	close access theOutput
end writeToFile

on insertMetaCharset(htmlContent)
	try
		-- Split the content by "<head>" and insert the meta tag immediately after it
		set AppleScript's text item delimiters to "<head>"
		set parts to text items of htmlContent
		if (count of parts) > 1 then
			set newHtmlContent to item 1 of parts & "<head><meta charset=\"UTF-8\">" & (items 2 thru -1 of parts as string)
			set AppleScript's text item delimiters to ""
			return newHtmlContent
		else
			return htmlContent
		end if
	on error
		return htmlContent
	end try
end insertMetaCharset

on replace_chars(this_text, search_string, replacement_string)
	set AppleScript's text item delimiters to search_string
	set item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to item_list as string
	set AppleScript's text item delimiters to ""
	return this_text
end replace_chars

tell application "Notes"
	activate
	-- Inform the user how many notes are stored in Notes
	display dialog "This is the export utility for Notes.app.

There are exactly " & (count of notes) & " notes in the application." with title "Notes Export" buttons {"Cancel", "Proceed"} cancel button "Cancel" default button "Proceed"
	
	-- Ask for the destination folder where HTML files will be saved
	set exportFolder to choose folder with prompt "Select the folder where you want to save the exported HTML files:"
	
	-- Ask whether to export by Folder or Individual Note
	set exportTypeList to {"Folders", "Individual Notes"}
	set exportTypeChoice to choose from list exportTypeList with prompt "Select export type:" default items {"Folders"}
	if exportTypeChoice is false then return
	set exportType to item 1 of exportTypeChoice
	
	if exportType is "Folders" then
		-- Get list of Apple Notes folders
		set noteFolders to folders
		set folderNames to {}
		repeat with aFolder in noteFolders
			set end of folderNames to name of aFolder
		end repeat
		
		-- Build hierarchical folder list with indentation to show structure
		set hierarchicalFolderNames to {}
		repeat with aFolder in noteFolders
			set folderLevel to 0
			set currentFolder to aFolder
			-- Check if this is a subfolder by counting parent folders
			try
				repeat
					set currentFolder to container of currentFolder
					set folderLevel to folderLevel + 1
				end repeat
			end try
			-- Add appropriate indentation based on folder level
			set indentation to ""
			repeat folderLevel times
				set indentation to indentation & "    "
			end repeat
			set end of hierarchicalFolderNames to indentation & name of aFolder
		end repeat
		
		-- Let user select folders with visual hierarchy
		set chosenFolders to choose from list hierarchicalFolderNames with prompt "Select folders to export notes from (indented items are subfolders):" with multiple selections allowed
		if chosenFolders is false then return
		
		-- Clean up the chosen folder names by removing indentation
		set cleanChosenFolders to {}
		repeat with folderName in chosenFolders
			set trimmedName to folderName
			repeat while trimmedName begins with " "
				set trimmedName to text 2 thru -1 of trimmedName
			end repeat
			set end of cleanChosenFolders to trimmedName
		end repeat
		set chosenFolders to cleanChosenFolders
		
		-- Loop through each chosen folder and export all its notes
		repeat with folderName in chosenFolders
			set selectedFolder to (first folder whose name is folderName)
			repeat with eachNote in (notes of selectedFolder)
				set noteName to name of eachNote
				set noteBody to body of eachNote
				set noteName to my replace_chars(noteName, ":", "-")
				set filename to ((exportFolder as string) & noteName & ".html")
				my writeToFile(filename, noteBody as text)
			end repeat
		end repeat
		
	else if exportType is "Individual Notes" then
		-- Get a list of all notes and build a list of their names
		set allNotes to notes
		set noteNames to {}
		repeat with aNote in allNotes
			set end of noteNames to name of aNote
		end repeat
		
		-- Let the user select one or more individual notes
		set chosenNotes to choose from list noteNames with prompt "Select one or more notes to export:" with multiple selections allowed
		if chosenNotes is false then return
		
		-- Export each chosen note
		repeat with noteName in chosenNotes
			set selectedNote to (first note whose name is noteName)
			set noteBody to body of selectedNote
			set safeNoteName to my replace_chars(noteName, ":", "-")
			set filename to ((exportFolder as string) & safeNoteName & ".html")
			my writeToFile(filename, noteBody as text)
		end repeat
	end if
	if exportType is "Individual Notes" then
		set exportCount to count of chosenNotes
	else if exportType is "Folders" then
		set exportCount to 0
		repeat with folderName in chosenFolders
			set theFolder to (first folder whose name is folderName)
			set exportCount to exportCount + (count of (notes of theFolder))
		end repeat
	end if
	display dialog "Based on your selection, there will be " & exportCount & " note(s) to be exported." with title "Notes Export" buttons {"Cancel", "Proceed"} cancel button "Cancel" default button "Proceed"
	
	display alert "Notes Export" message "Export completed successfully." as informational
end tell