--------------------------------------------------------------------------------
-- Helper: Replace occurrences of a substring in a text string.
on replaceText(theText, searchString, replacementString)
	set AppleScript's text item delimiters to searchString
	set itemList to every text item of theText
	set AppleScript's text item delimiters to replacementString
	set newText to itemList as string
	set AppleScript's text item delimiters to ""
	return newText
end replaceText

--------------------------------------------------------------------------------
tell application "Notes"
	activate
	
	--------------------------------------------------------------------------------
	-- Build a list of account names and let the user choose one.
	set accountNames to {}
	repeat with anAccount in accounts
		copy (name of anAccount as string) to end of accountNames
	end repeat
	set chosenAccountName to choose from list accountNames with prompt "Select the Apple Notes account to export from:" without multiple selections allowed
	if chosenAccountName is false then return
	set chosenAccountName to item 1 of chosenAccountName
	set targetAccount to first account whose name is chosenAccountName
	
	--------------------------------------------------------------------------------
	-- Build a list of folders (with note counts) from the chosen account.
	set folderList to {}
	repeat with aFolder in folders of targetAccount
		set folderCount to count of (notes of aFolder)
		copy ((name of aFolder as string) & " (" & folderCount & " notes)") to end of folderList
	end repeat
	-- Add "All Notes" option.
	set totalNotes to count of (notes of targetAccount)
	set folderList to {"All Notes (" & totalNotes & " notes)"} & folderList
	
	-- Let the user choose one or more folders.
	set exportChoices to choose from list folderList with prompt "Select which folders to export (hold CMD to select multiple):" with multiple selections allowed
	if exportChoices is false then return
	
	--------------------------------------------------------------------------------
	-- Gather notes from the selected folders as a static list.
	set notesToExport to {}
	repeat with choice in exportChoices
		if choice starts with "All Notes" then
			set notesToExport to (notes of targetAccount) as list
			exit repeat
		else
			-- Extract folder name (ignoring the count)
			set AppleScript's text item delimiters to " ("
			set folderName to text item 1 of choice
			set AppleScript's text item delimiters to ""
			try
				set targetFolder to (first folder of targetAccount whose name is folderName)
				set notesToExport to notesToExport & ((notes of targetFolder) as list)
			end try
		end if
	end repeat
	
	--------------------------------------------------------------------------------
	-- Ask user for an output folder.
	set outputFolder to choose folder with prompt "Choose an output location. (The folder structure will be preserved.)"
	
	--------------------------------------------------------------------------------
	-- Process each note.
	-- Capture the default account name so that the container chain stops correctly.
	set defaultAccountName to name of targetAccount
	repeat with aNote in notesToExport
		-- Skip locked notes.
		if password protected of aNote then
			-- Skip without processing.
		else
			-- Retrieve note properties.
			set noteBody to body of aNote as string
			-- Use the note's title as the filename (typically the first line in Apple Notes).
			set noteTitle to name of aNote
			set noteID to id of aNote as string
			
			--------------------------------------------------------------------------------
			-- Build extra HTML for attachments (video, audio, PDF) – see previous polishing.
			set extraHTML to ""
			try
				set attList to attachments of aNote
			on error
				set attList to {}
			end try
			if (count of attList) > 0 then
				repeat with anAtt in attList
					set attName to name of anAtt
					-- Convert to lower case for extension testing.
					set lowerName to do shell script "echo " & quoted form of attName & " | tr '[:upper:]' '[:lower:]'"
					if lowerName ends with ".webm" or lowerName ends with ".mp4" or lowerName ends with ".mov" then
						set extraHTML to extraHTML & "<video src=\"attachments/" & attName & "\" controls>" & return & "  <p>" & return & "    Your browser doesn't support HTML video. Here is a" & return & "    <a href=\"attachments/" & attName & "\">link to the video</a> instead." & return & "  </p>" & return & "</video>" & return
					else if lowerName ends with ".ogg" then
						set extraHTML to extraHTML & "<audio controls>" & return & "  <source src=\"attachments/" & attName & "\" type=\"audio/ogg\">" & return & "  Your browser does not support the audio tag." & return & "</audio>" & return
					else if lowerName ends with ".mp3" then
						set extraHTML to extraHTML & "<audio controls>" & return & "  <source src=\"attachments/" & attName & "\" type=\"audio/mpeg\">" & return & "  Your browser does not support the audio tag." & return & "</audio>" & return
					else if lowerName ends with ".m4a" then
						set extraHTML to extraHTML & "<audio controls>" & return & "  <source src=\"attachments/" & attName & "\" type=\"audio/mp4\">" & return & "  Your browser does not support the audio tag." & return & "</audio>" & return
					else if lowerName ends with ".pdf" then
						set extraHTML to extraHTML & "<p><a href=\"attachments/" & attName & "\">" & attName & "</a></p>" & return
					end if
				end repeat
			end if
			-- Append extra HTML to the note body.
			set noteBody to noteBody & return & extraHTML
			
			--------------------------------------------------------------------------------
			-- Build the mirrored folder structure.
			try
				set currentContainer to container of aNote
				set internalPath to name of currentContainer
			on error
				set internalPath to ""
			end try
			-- Walk up the container chain until the default account is reached.
			repeat while (class of currentContainer is not account) and ((name of currentContainer) is not equal to defaultAccountName)
				set currentContainer to container of currentContainer
				if (class of currentContainer is not account) and ((name of currentContainer) is not equal to defaultAccountName) then
					set internalPath to (name of currentContainer & "/" & internalPath)
				end if
			end repeat
			
			--------------------------------------------------------------------------------
			-- Create the output directory based on the mirrored structure.
			if internalPath ≠ "" then
				set dirPath to (POSIX path of outputFolder) & internalPath & "/"
			else
				set dirPath to (POSIX path of outputFolder)
			end if
			do shell script "mkdir -p " & quoted form of dirPath
			
			--------------------------------------------------------------------------------
			-- Build a sanitized file name using the note title.
			set baseFileName to noteTitle
			if (length of baseFileName) > 250 then set baseFileName to text 1 thru 250 of baseFileName
			set baseFileName to my replaceText(baseFileName, ":", "-")
			set baseFileName to my replaceText(baseFileName, "/", "-")
			set baseFileName to my replaceText(baseFileName, "$", "")
			set baseFileName to my replaceText(baseFileName, "\"", "-")
			set baseFileName to my replaceText(baseFileName, "\\", "-")
			set filePath to dirPath & baseFileName & ".html"
			
			--------------------------------------------------------------------------------
			-- Write the note (with extra HTML) to an HTML file (UTF-8 encoded).
			try
				set fileRef to open for access (POSIX file filePath) with write permission
				set eof of fileRef to 0
				write noteBody to fileRef as «class utf8»
				close access fileRef
			on error errMsg
				try
					close access (POSIX file filePath)
				end try
				display dialog "Error writing file: " & errMsg buttons {"OK"} default button 1
			end try
			
			--------------------------------------------------------------------------------
			-- Now polish the HTML file:
			-- (1) Replace multiple consecutive <br> tags with a single <br>
			-- (2) If there are consecutive rows exactly matching "<div><br><div>" (separated by a newline), reduce them to one.
			try
				-- Read the file contents.
				set fileContent to read (POSIX file filePath) as «class utf8»
				
				-- Step 1: Replace occurrences of "<br><br>" with "<br>" repeatedly.
				repeat while fileContent contains "<br><br>"
					set fileContent to my replaceText(fileContent, "<br><br>", "<br>")
				end repeat
				
				-- Write the cleaned content back to the file.
				set fileRef to open for access (POSIX file filePath) with write permission
				set eof of fileRef to 0
				write fileContent to fileRef as «class utf8»
				close access fileRef
			on error errClean
				try
					close access (POSIX file filePath)
				end try
				display dialog "Error cleaning file: " & errClean buttons {"OK"} default button 1
			end try
			
			--------------------------------------------------------------------------------
			-- Export attachments (if any) into an "attachments" subfolder.
			try
				if (count of attList) > 0 then
					set attDir to dirPath & "attachments/"
					do shell script "mkdir -p " & quoted form of attDir
					repeat with anAtt in attList
						set attName to name of anAtt
						set attFilePath to attDir & attName
						try
							save anAtt in (POSIX file attFilePath)
						on error errSave
							-- Optionally log or ignore attachment errors.
						end try
					end repeat
				end if
			end try
		end if
	end repeat
	
	--------------------------------------------------------------------------------
	-- Notify the user that the export is complete.
	display dialog "Export completed." buttons {"OK"} default button "OK"
end tell
