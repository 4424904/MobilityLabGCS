#!/usr/bin/env python3
"""Windows installer (QGC deploy/windows/nullsoft_installer.nsi) additions for MobilityLab GCS:
desktop shortcut (removed on uninstall), "launch after install" on the finish page, Korean + English pages.
Run from the QGC checkout root (tools/ci_prepare.sh)."""
import sys

P = "deploy/windows/nullsoft_installer.nsi"
s = open(P, encoding="utf-8").read()


def rep(a, b):
    global s
    if a not in s:
        sys.exit(f"patch_installer: anchor not found: {a[:60]!r}")
    s = s.replace(a, b, 1)


# start-menu folder also in silent installs (the page does not run there) and never empty on uninstall
rep('!insertmacro MUI_PAGE_STARTMENU Application $StartMenuFolder',
    '!define MUI_STARTMENUPAGE_DEFAULTFOLDER "${APPNAME}"\n!insertmacro MUI_PAGE_STARTMENU Application $StartMenuFolder')
rep('    !insertmacro MUI_STARTMENU_GETFOLDER Application $StartMenuFolder\n',
    '    !insertmacro MUI_STARTMENU_GETFOLDER Application $StartMenuFolder\n'
    '    ${If} $StartMenuFolder == ""\n        StrCpy $StartMenuFolder "${APPNAME}"\n    ${EndIf}\n')
rep('!insertmacro MUI_PAGE_INSTFILES\n',
    '!insertmacro MUI_PAGE_INSTFILES\n'
    '!define MUI_FINISHPAGE_RUN "$INSTDIR\\bin\\${EXENAME}.exe"\n'
    '!insertmacro MUI_PAGE_FINISH\n')
rep('!insertmacro MUI_LANGUAGE "English"', '!insertmacro MUI_LANGUAGE "Korean"\n!insertmacro MUI_LANGUAGE "English"')
rep('        !insertmacro DemoteShortCut "$SMPROGRAMS\\$StartMenuFolder\\${APPNAME} (GPU Safe Mode).lnk"\n'
    '    !insertmacro MUI_STARTMENU_WRITE_END\n',
    '        !insertmacro DemoteShortCut "$SMPROGRAMS\\$StartMenuFolder\\${APPNAME} (GPU Safe Mode).lnk"\n'
    '    !insertmacro MUI_STARTMENU_WRITE_END\n'
    '    CreateShortCut "$DESKTOP\\${APPNAME}.lnk" "$INSTDIR\\bin\\${EXENAME}.exe" "" "$INSTDIR\\bin\\${EXENAME}.exe" 0\n'
    '    ${If} ${Silent}\n'
    '        CreateDirectory "$SMPROGRAMS\\${APPNAME}"\n'
    '        CreateShortCut "$SMPROGRAMS\\${APPNAME}\\${APPNAME}.lnk" "$INSTDIR\\bin\\${EXENAME}.exe" "" "$INSTDIR\\bin\\${EXENAME}.exe" 0\n'
    '    ${EndIf}\n')
rep('    RMDir /r /REBOOTOK "$SMPROGRAMS\\$StartMenuFolder\\"\n',
    '    RMDir /r /REBOOTOK "$SMPROGRAMS\\$StartMenuFolder\\"\n'
    '    Delete "$DESKTOP\\${APPNAME}.lnk"\n')
open(P, "w", encoding="utf-8").write(s)
print("installer: desktop shortcut, launch-after-install, Korean pages")
