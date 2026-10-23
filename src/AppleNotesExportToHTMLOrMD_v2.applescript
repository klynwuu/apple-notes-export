--------------------------------------------------------------------------------
-- Apple Notes Exporter v2: folders -> HTML or Markdown files (checked on macOS 27.0.1)
--
-- Changes from AppleNotesExportToHTMLOrMD_v1:
--   * Folders are listed by path ("Parent/Child"), so same-named folders can be told apart,
--     and nested folders keep their place in the output tree.
--   * Folder paths come from one pass over the folder tree instead of walking each
--     note's container (about 1 s per note on a large account).
--   * Inline images (Notes stores them as data: URIs in the body) are written to
--     attachments/<note>/image-N.ext and linked. v1 relied on `save attachment`,
--     which fails on macOS 27, and appended links to files that were never written.
--   * Notes with the same title no longer overwrite each other ("Title (2).md").
--   * Markdown mode converts headings, bold/italic/strike, monospaced text, lists,
--     links, images and tables instead of leaving raw HTML tags.
--   * One bad note no longer stops the run with a dialog; failures are listed at the end.
--   * Recently Deleted (listed by scripts as an ordinary folder) is not exported.
--   * Titles are HTML-escaped in <title>.
--
-- Attachments that are not inline images (PDF, audio, drawings, scans) cannot be
-- extracted by script on macOS 27. For those notes use Notes > Share > Export as
-- Markdown, which keeps every attachment.
--------------------------------------------------------------------------------

on run
	tell application "Notes"
		activate
		set accountNames to name of every account
		if (count of accountNames) is 1 then
			set chosenAccountName to item 1 of accountNames
		else
			set picked to choose from list accountNames with prompt "Select the Apple Notes account to export from:" without multiple selections allowed
			if picked is false then return
			set chosenAccountName to item 1 of picked
		end if
		set targetAccount to account chosenAccountName
	end tell

	set folderTable to my buildFolderTable(targetAccount)
	set choices to {"All Notes"}
	repeat with f in folderTable
		set end of choices to (fPath of f) & " (" & (fCount of f) & " notes)"
	end repeat
	set picked to choose from list choices with prompt "Select folders to export (hold ⌘ to select several; subfolders are included):" with multiple selections allowed
	if picked is false then return

	set exportMode to button returned of (display dialog "Export as HTML or Markdown?" buttons {"HTML", "Markdown"} default button "Markdown")
	set outputFolder to POSIX path of (choose folder with prompt "Choose an output folder (the folder structure is mirrored inside it):")

	set selectedPaths to {}
	repeat with c in picked
		set c to c as text
		if c is "All Notes" then
			set selectedPaths to {""}
			exit repeat
		end if
		set end of selectedPaths to my stripCount(c)
	end repeat

	set report to my exportFolders(folderTable, selectedPaths, outputFolder, exportMode)
	display dialog report buttons {"OK"} default button "OK"
end run

--------------------------------------------------------------------------------
-- Folder table: {fRef, fPath, fCount} for every folder, paths built from parent links.

on buildFolderTable(targetAccount)
	tell application "Notes"
		set allFolders to every folder of targetAccount
		set ids to id of every folder of targetAccount
		set names to name of every folder of targetAccount
		set parentOf to {}
		repeat with i from 1 to count of allFolders
			set childIds to id of every folder of (item i of allFolders)
			repeat with cid in childIds
				set end of parentOf to {child:(cid as text), parent:(item i of ids)}
			end repeat
		end repeat
	end tell
	set folderList to {}
	repeat with i from 1 to count of ids
		set thePath to item i of names
		set cur to item i of ids
		repeat 64 times
			set p to my lookupParent(parentOf, cur)
			if p is missing value then exit repeat
			set thePath to (item (my indexOf(ids, p)) of names) & "/" & thePath
			set cur to p
		end repeat
		-- Recently Deleted shows up as an ordinary folder to scripts; leave it out.
		if {"Recently Deleted", "最近删除", "最近刪除"} does not contain thePath then
			tell application "Notes" to set n to count of notes of (item i of allFolders)
			set end of folderList to {fRef:(item i of allFolders), fPath:thePath, fCount:n}
		end if
	end repeat
	return my sortByPath(folderList)
end buildFolderTable

on lookupParent(parentOf, childId)
	repeat with r in parentOf
		if child of r is childId then return parent of r
	end repeat
	return missing value
end lookupParent

on indexOf(theList, theItem)
	repeat with i from 1 to count of theList
		if item i of theList is theItem then return i
	end repeat
	return 0
end indexOf

on sortByPath(folderList)
	set n to count of folderList
	repeat with i from 2 to n
		set x to item i of folderList
		set j to i - 1
		repeat while j ≥ 1
			considering case
				set bigger to (fPath of item j of folderList) > (fPath of x)
			end considering
			if not bigger then exit repeat
			set item (j + 1) of folderList to item j of folderList
			set j to j - 1
		end repeat
		set item (j + 1) of folderList to x
	end repeat
	return folderList
end sortByPath

on stripCount(choice)
	set AppleScript's text item delimiters to " ("
	set parts to text items of choice
	if (count of parts) > 1 then
		set parts to items 1 thru -2 of parts
	end if
	set joined to parts as text
	set AppleScript's text item delimiters to ""
	return joined
end stripCount

--------------------------------------------------------------------------------
-- Export. selectedPaths: folder paths ("" = everything); subfolders are included.

on exportFolders(folderTable, selectedPaths, outputFolder, exportMode)
	if outputFolder does not end with "/" then set outputFolder to outputFolder & "/"
	if exportMode is "HTML" then
		set ext to ".html"
	else
		set ext to ".md"
	end if
	set exported to 0
	set skipped to 0
	set failures to {}
	set usedNames to {}
	repeat with f in folderTable
		if my isSelected(fPath of f, selectedPaths) then
			set dirPath to outputFolder & my safePath(fPath of f) & "/"
			do shell script "mkdir -p " & quoted form of dirPath
			tell application "Notes" to set theNotes to every note of (fRef of f)
			repeat with aNote in theNotes
				set noteTitle to "(untitled)"
				try
					tell application "Notes"
						set noteTitle to name of aNote
						set isLocked to password protected of aNote
					end tell
					if isLocked then
						set skipped to skipped + 1
					else
						tell application "Notes" to set noteBody to body of aNote
						set baseName to my uniqueName(usedNames, dirPath, my safeName(noteTitle))
						set noteBody to my extractImages(noteBody, dirPath, baseName)
						if exportMode is "HTML" then
							set fileText to my wrapHTML(my cleanHTML(noteBody), noteTitle)
						else
							set fileText to my toMarkdown(noteBody)
						end if
						my writeUTF8(dirPath & baseName & ext, fileText)
						set exported to exported + 1
					end if
				on error errMsg
					set end of failures to noteTitle & ": " & errMsg
				end try
			end repeat
		end if
	end repeat
	set report to "Exported " & exported & " note(s) to " & outputFolder
	if skipped > 0 then set report to report & return & "Skipped " & skipped & " locked note(s)."
	if (count of failures) > 0 then
		set AppleScript's text item delimiters to return
		set report to report & return & (count of failures) & " failed:" & return & (failures as text)
		set AppleScript's text item delimiters to ""
	end if
	return report
end exportFolders

on isSelected(thePath, selectedPaths)
	repeat with p in selectedPaths
		set p to p as text
		if p is "" or thePath is p or thePath starts with (p & "/") then return true
	end repeat
	return false
end isSelected

--------------------------------------------------------------------------------
-- File names

on safeName(theName)
	set theName to my replaceText(theName, return, " ")
	set theName to my replaceText(theName, linefeed, " ")
	repeat with ch in {"/", ":", "\\", "\"", "*", "?", "<", ">", "|"}
		set theName to my replaceText(theName, ch as text, "-")
	end repeat
	if (length of theName) > 80 then set theName to text 1 thru 80 of theName
	repeat while theName starts with "." or theName starts with " "
		if (length of theName) is 1 then return "Untitled"
		set theName to text 2 thru -1 of theName
	end repeat
	if theName is "" then return "Untitled"
	return theName
end safeName

on safePath(thePath)
	set AppleScript's text item delimiters to "/"
	set parts to text items of thePath
	set AppleScript's text item delimiters to ""
	set cleaned to {}
	repeat with p in parts
		set end of cleaned to my safeName(p as text)
	end repeat
	set AppleScript's text item delimiters to "/"
	set joined to cleaned as text
	set AppleScript's text item delimiters to ""
	return joined
end safePath

on uniqueName(usedNames, dirPath, baseName)
	set candidate to baseName
	set k to 2
	repeat while usedNames contains (dirPath & candidate)
		set candidate to baseName & " (" & k & ")"
		set k to k + 1
	end repeat
	set end of usedNames to (dirPath & candidate)
	return candidate
end uniqueName

--------------------------------------------------------------------------------
-- Inline images: src="data:image/png;base64,…" -> attachments/<note>/image-N.png

on extractImages(theBody, dirPath, baseName)
	set marker to "src=\"data:"
	if theBody does not contain marker then return theBody
	set AppleScript's text item delimiters to marker
	set parts to text items of theBody
	set AppleScript's text item delimiters to ""
	set relDir to "attachments/" & baseName & "/"
	do shell script "mkdir -p " & quoted form of (dirPath & relDir)
	set rebuilt to item 1 of parts
	repeat with i from 2 to count of parts
		set chunk to item i of parts
		set q to offset of "\"" in chunk
		set uri to text 1 thru (q - 1) of chunk
		set tailText to text q thru -1 of chunk
		set b64Start to offset of ";base64," in uri
		set mime to text 1 thru (b64Start - 1) of uri
		set fileName to "image-" & (i - 1) & my extensionFor(mime)
		set tmpPath to do shell script "mktemp -t notes-export"
		my writeUTF8(tmpPath, text (b64Start + 8) thru -1 of uri)
		do shell script "base64 -D -i " & quoted form of tmpPath & " -o " & quoted form of (dirPath & relDir & fileName) & "; rm -f " & quoted form of tmpPath
		set rebuilt to rebuilt & "src=\"" & my urlPath(relDir & fileName) & tailText
	end repeat
	return rebuilt
end extractImages

on extensionFor(mime)
	if mime is "image/jpeg" then return ".jpg"
	if mime is "image/png" then return ".png"
	if mime is "image/gif" then return ".gif"
	if mime is "image/heic" then return ".heic"
	if mime is "image/webp" then return ".webp"
	if mime is "image/tiff" then return ".tiff"
	return ".bin"
end extensionFor

on urlPath(thePath)
	set thePath to my replaceText(thePath, "%", "%25")
	set thePath to my replaceText(thePath, " ", "%20")
	set thePath to my replaceText(thePath, "(", "%28")
	return my replaceText(thePath, ")", "%29")
end urlPath

--------------------------------------------------------------------------------
-- HTML

on cleanHTML(theBody)
	repeat while theBody contains "<div><br></div>" & linefeed & "<div><br></div>"
		set theBody to my replaceText(theBody, "<div><br></div>" & linefeed & "<div><br></div>", "<div><br></div>")
	end repeat
	return theBody
end cleanHTML

on wrapHTML(theBody, noteTitle)
	return "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>" & my escapeHTML(noteTitle) & "</title>
  <style>
    body { max-width: 46rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.6; font-family: -apple-system, \"PingFang SC\", sans-serif; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; } td { border: 1px solid #ccc; padding: 3px 6px; vertical-align: top; }
  </style>
</head>
<body>
" & theBody & "
</body>
</html>
"
end wrapHTML

on escapeHTML(t)
	set t to my replaceText(t, "&", "&amp;")
	set t to my replaceText(t, "<", "&lt;")
	return my replaceText(t, ">", "&gt;")
end escapeHTML

--------------------------------------------------------------------------------
-- Markdown: one pass over the tags of the HTML dialect Notes produces (a <div> per line,
-- nested lists as siblings of <li>, tables inside <object>). Good for reading and archiving;
-- the agent CLI (OPC SKILLs repo, apple-notes/scripts/notes.py) converts more strictly.

on toMarkdown(theBody)
	set flat to my replaceText(theBody, linefeed, "") -- resets the delimiters, so split afterwards
	set AppleScript's text item delimiters to "<"
	set pieces to text items of flat
	set AppleScript's text item delimiters to ""
	set md to my decodeEntities(item 1 of pieces)
	set listStack to {}
	set counters to {}
	set inTable to false
	set rowIndex to 0
	set cellCount to 0
	set linkStart to -1
	set linkHref to ""
	repeat with i from 2 to count of pieces
		set piece to item i of pieces
		set gt to offset of ">" in piece
		if gt is 0 then
			set md to md & "<" & my decodeEntities(piece)
		else
			set tagText to text 1 thru (gt - 1) of piece
			set txt to ""
			if gt < (length of piece) then set txt to text (gt + 1) thru -1 of piece
			set isClose to tagText starts with "/"
			set tagName to my tagNameOf(tagText)
			if tagName is "br" then
				if not my brIsTrailing(pieces, i) then set md to md & linefeed
			else if {"h1", "h2", "h3"} contains tagName then
				if not isClose then set md to md & (text 1 thru ((character 2 of tagName) as integer) of "###") & " "
			else if {"b", "strong"} contains tagName then
				set md to md & "**"
			else if {"i", "em"} contains tagName then
				set md to md & "*"
			else if {"strike", "s", "del"} contains tagName then
				set md to md & "~~"
			else if tagName is "tt" then
				set md to md & "`"
			else if tagName is "div" then
				if isClose and inTable then
					set md to md & " "
				else if isClose then
					set md to md & linefeed
				end if
			else if {"ul", "ol"} contains tagName then
				if isClose then
					set listStack to my dropLast(listStack)
					set counters to my dropLast(counters)
				else
					set end of listStack to tagName
					set end of counters to 0
				end if
			else if tagName is "li" then
				if isClose then
					set md to md & linefeed
				else
					set depth to count of listStack
					if md is not "" and md does not end with linefeed then set md to md & linefeed
					set indent to ""
					repeat (depth - 1) times
						set indent to indent & "   "
					end repeat
					if depth > 0 and item depth of listStack is "ol" then
						set item depth of counters to (item depth of counters) + 1
						set md to md & indent & (item depth of counters) & ". "
					else
						set md to md & indent & "- "
					end if
				end if
			else if tagName is "a" then
				if not isClose then
					set linkHref to my attrValue(tagText, "href")
					set linkStart to length of md
				else if linkStart ≥ 0 then
					set linkText to ""
					if linkStart < (length of md) then set linkText to text (linkStart + 1) thru -1 of md
					set head to ""
					if linkStart > 0 then set head to text 1 thru linkStart of md
					if linkText is "" or linkText is linkHref then
						set md to head & linkHref
					else
						set md to head & "[" & linkText & "](" & linkHref & ")"
					end if
					set linkStart to -1
				end if
			else if tagName is "img" then
				set md to md & "![](" & my attrValue(tagText, "src") & ")"
			else if tagName is "hr" then
				if md is not "" and md does not end with linefeed then set md to md & linefeed
				set md to md & "---" & linefeed
			else if tagName is "table" then
				set inTable to not isClose
				set rowIndex to 0
				if md is not "" and md does not end with linefeed then set md to md & linefeed
			else if tagName is "tr" then
				if isClose then
					set md to md & linefeed
					set rowIndex to rowIndex + 1
					if rowIndex is 1 then
						set sep to "|"
						repeat cellCount times
							set sep to sep & " --- |"
						end repeat
						set md to md & sep & linefeed
					end if
				else
					set md to md & "|"
					set cellCount to 0
				end if
			else if tagName is "td" then
				if isClose then
					set md to md & "|"
					set cellCount to cellCount + 1
				else
					set md to md & " "
				end if
			end if
			set txt to my decodeEntities(txt)
			if inTable then set txt to my replaceText(txt, "|", "\\|")
			set md to md & txt
		end if
	end repeat
	-- Notes splits formatting runs: **a****b** -> **ab**
	set md to my replaceText(md, "****", "")
	set md to my replaceText(md, "  |", " |")
	repeat while md contains (linefeed & linefeed & linefeed)
		set md to my replaceText(md, linefeed & linefeed & linefeed, linefeed & linefeed)
	end repeat
	return md
end toMarkdown

-- A <br> right before the end of its line (</div>, </li>, </td>, a heading) adds no line.
on brIsTrailing(pieces, i)
	repeat with j from (i + 1) to count of pieces
		set piece to item j of pieces
		set gt to offset of ">" in piece
		if gt is 0 or not (piece starts with "/") then return false
		set tagName to my tagNameOf(text 1 thru (gt - 1) of piece)
		if {"div", "li", "td", "h1", "h2", "h3"} contains tagName then return true
		if not ({"b", "i", "u", "span", "font", "tt", "strike", "em", "strong"} contains tagName) then return false
		if gt < (length of piece) then return false
	end repeat
	return true
end brIsTrailing

on tagNameOf(tagText)
	if tagText starts with "/" then set tagText to text 2 thru -1 of tagText
	set nameText to ""
	repeat with ch in (characters of tagText)
		if (ch as text) is in {" ", "/", tab} then exit repeat
		set nameText to nameText & ch
	end repeat
	return nameText
end tagNameOf

on attrValue(tagText, attrName)
	set k to offset of (attrName & "=\"") in tagText
	if k is 0 then return ""
	set valueText to text (k + (length of attrName) + 2) thru -1 of tagText
	set q to offset of "\"" in valueText
	if q is 0 then return valueText
	if q is 1 then return ""
	return my decodeEntities(text 1 thru (q - 1) of valueText)
end attrValue

on dropLast(theList)
	if (count of theList) < 2 then return {}
	return items 1 thru -2 of theList
end dropLast

on decodeEntities(t)
	-- Notes also writes the legacy forms without ";" (return &quothi&quot)
	repeat with p in {{"&nbsp;", " "}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&#39;", "'"}, ¬
		{"&nbsp", " "}, {"&lt", "<"}, {"&gt", ">"}, {"&quot", "\""}, {"&amp;", "&"}, {"&amp", "&"}}
		set t to my replaceText(t, item 1 of p, item 2 of p)
	end repeat
	return t
end decodeEntities

--------------------------------------------------------------------------------
-- Helpers

on replaceText(theText, searchString, replacementString)
	set AppleScript's text item delimiters to searchString
	set itemList to every text item of theText
	set AppleScript's text item delimiters to replacementString
	set newText to itemList as text
	set AppleScript's text item delimiters to ""
	return newText
end replaceText

on writeUTF8(posixPath, theText)
	set fileRef to open for access (POSIX file posixPath) with write permission
	try
		set eof of fileRef to 0
		write theText to fileRef as «class utf8»
		close access fileRef
	on error errMsg number errNum
		close access fileRef
		error errMsg number errNum
	end try
end writeUTF8
