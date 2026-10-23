# Folder Level Apple Notes Exporter

Code base enhanced from [notes-export/notesExport.applescript at master · robertgaal/notes-export](https://github.com/robertgaal/notes-export/blob/master/notesExport.applescript)

| Script | Purpose |
|---|---|
| `src/AppleNotesExportToHTMLOrMD_v2.applescript` | **Current.** Folders → HTML or Markdown, nested folders mirrored, inline images extracted |
| `src/AppleNotesExportToHTMLOrMD_v1.applescript` | Previous HTML/Markdown exporter (kept for reference) |
| `src/AppleNotesExportToHTML_v3.applescript` | HTML-only predecessor, guide below |
| `src/AppleNotesExportToReminderItem_v1/v2.applescript` | Selected note → Reminder with a deep link, guide below |

## Exporter v2 (checked on macOS 27.0.1)

Open `src/AppleNotesExportToHTMLOrMD_v2.applescript` in Script Editor and run it, or run
`osascript src/AppleNotesExportToHTMLOrMD_v2.applescript`. Pick folders (shown as paths, subfolders
included), HTML or Markdown, and an output folder. The first run asks to let Script Editor (or your
terminal) control Notes.

```
Output/
├── Work/
│   ├── Weekly Review.md
│   ├── Weekly Review (2).md          # same title, no longer overwritten
│   └── attachments/Weekly Review/image-1.png
└── Work/Clients/Brief.md
```

What changed from v1:

- Folders are listed by path, so two folders with the same name can be told apart; nested folders keep their place.
- Folder paths come from one pass over the folder tree instead of walking every note's container (about 1 s per note on a large account).
- Inline images, which Notes keeps as `data:` URIs in the body, are written to `attachments/<note>/image-N.ext` and linked. v1 relied on `save attachment`, which fails on macOS 27, so its attachment links pointed at files that were never written.
- Notes with the same title no longer overwrite each other.
- Markdown mode converts headings, bold/italic/strikethrough, monospaced text, nested and numbered lists, links, images and tables instead of leaving HTML tags in the file.
- A failing note is listed in the final report instead of stopping the run with a dialog; Recently Deleted is skipped.

Limits on macOS 27: attachments that are not inline images (PDF, audio, drawings, scans, link cards) cannot be extracted by script; checklists export as plain list items. For a complete single-note export use Notes > Share > Export as Markdown (new in macOS 27), which writes every attachment to an `Attachments` folder.

For agents and the command line, the `apple-notes` skill in the OPC SKILLs repo (`agentic-tools/SKILLs/apple-notes/scripts/notes.py`) searches, reads, writes and exports notes with a stricter HTML ↔ Markdown converter.

## how to Run `AppleNotesExportToHTML_v3.applescript`

copy the script to Apple script editor and run it.

# Apple Notes Exporter To HTML v3 Guide

## 📋 What This Script Does
This script exports Apple Notes to formatted HTML files with:
- Preserved folder structure
- Attachments handling (audio/video/PDF embeds)
- Clean HTML formatting
- Open Graph metadata support
- Customizable templates
- Multi-account support

## 🚀 How to Use

1. **Run the Script**  
   Double-click the `.applescript` file or run via Script Editor

2. **Select Account**  
   Choose which Notes account to export from

3. **Choose Folders**  
   Select specific folders or "All Notes"

4. **Pick Output Location**  
   Select a destination folder (empty directory recommended)

5. **Let It Run**  
   The script will:
   - Create mirrored folder structure
   - Export notes as HTML
   - Save attachments
   - Clean up formatting
   - Add metadata headers

## 🔄 Workflow Diagram
```mermaid
flowchart TD
A[Start Script] --> B[Select Notes Account]
B --> C[Choose Folders to Export]
C --> D[Select Output Folder]
D --> E[Process Notes]
E --> F[Export HTML + Attachments]
F --> G[Clean HTML Formatting]
G --> H[Add Metadata Headers]
H --> I[Complete Export]
```

## 🛠 Customization Options

### 1. HTML Metadata (in `wrapHTML` handler)

### 2. HTML Styling
Modify the CSS in the `wrapHTML` handler:

### 3. Attachment Handling
Supported formats in `attList` loop:
- Video: .webm, .mp4, .mov
- Audio: .ogg, .mp3, .m4a
- Documents: .pdf

### 4. File Naming
Adjust sanitization rules:
```applescript
set baseFileName to my replaceText(baseFileName, ":", "-")
set baseFileName to my replaceText(baseFileName, "/", "-")
```

### 5. HTML Cleaning
Modify `preProcessHTML` for different cleanup needs:
```applescript
repeat while fileContent contains "<br><br>"
    set fileContent to my replaceText(fileContent, "<br><br>", "<br>")
end repeat
```

## 📂 Export Structure
```
ExportFolder/
├── Folder1/
│   ├── Note1.html
│   └── attachments/
│       ├── video.mp4
│       └── doc.pdf
└── Folder2/
    ├── Note2.html
    └── Subfolder/
        └── Note3.html
```

## ⚠️ Important Notes
1. Requires macOS Catalina (10.15) or newer
2. Needs permission to access Notes app
3. Password-protected notes are skipped
4. First run may require:
   - System Preferences > Security & Privacy > Automation
   - Check "Script Editor" and "Notes"

## 🐛 Error Handling
The script includes:
- File access error recovery
- Attachment failure fallbacks
- User-friendly error dialogs
- Cleanup routines for partial exports

## 🔄 Update Frequency
Can safely export multiple times - overwrites existing files but preserves folder structure.

# Apple Notes Export to Reminder Item (v1)

## 📋 What This Script Does
This script creates a reminder from a selected note in Apple Notes with:
- Note title as the reminder title
- First 100 characters of the note's second line as reminder body
- Deep links back to the original note (desktop and mobile versions)
- Due date set to the coming Saturday at 10:00 AM
- Reminder placed in the "Default" list

## 🚀 How to Use

1. **Open Apple Notes**
   Select the note you want to create a reminder for

2. **Run the Script**  
   Double-click the `.applescript` file or run via Script Editor

3. **Verification**
   - The selected note will open in a separate window
   - The script will extract information and create a reminder
   - Reminders app will open showing the newly created item

## 🔄 Workflow Diagram
```mermaid
flowchart TD
    A[Start Script] --> B[Get Selected Note]
    B --> C[Extract Note Title & Content]
    C --> D[Query NoteStore.sqlite Database]
    D --> E[Generate Deep Links]
    E --> F[Calculate Next Saturday]
    F --> G[Create Reminder]
    G --> H[Open Reminders App]
```

## 📝 Technical Details

### Note Identification
The script uses SQLite to query the NoteStore.sqlite database to retrieve the real UUID of the note, allowing for proper deep linking.

> [!WARNING]
> Make sure go to System Preferences > Security & Privacy > Full Disk Access for Script Editor and enable it.

```applescript
-- Query the NoteStore.sqlite database to get the real note identifier (UUID)
set sqliteQuery to "SELECT ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK=" & internalPK & ";"
try
	set realNoteID to do shell script "/usr/bin/sqlite3 ~/Library/Group\\ Containers/group.com.apple.notes/NoteStore.sqlite " & quoted form of sqliteQuery
on error errMsg number errNum
	display dialog "Error retrieving note identifier: " & errMsg
	return
end try
```

### Deep Links
Two deep links are created:
- `notes://showNote?identifier=UUID` (Desktop)
- `mobilenotes://showNote?identifier=UUID` (iOS)

### Date Calculation
Automatically calculates the coming Saturday at 10:00 AM for the reminder due date.

## ⚠️ Important Notes
1. Requires macOS with access to both Notes and Reminders apps
2. Needs permission to:
   - Control Apple Notes
   - Control Reminders
   - Access your Notes database
3. Will create reminders in the "Default" list (create this list if it doesn't exist)
4. First-time use requires Automation permissions in System Preferences

