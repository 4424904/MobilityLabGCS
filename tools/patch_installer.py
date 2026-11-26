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


rep('!insertmacro MUI_PAGE_INSTFILES\n',
    '!insertmacro MUI_PAGE_INSTFILES\n'
    '!define MUI_FINISHPAGE_RUN "$INSTDIR\\bin\\${EXENAME}.exe"\n'
    '!insertmacro MUI_PAGE_FINISH\n')
rep('!insertmacro MUI_LANGUAGE "English"', '!insertmacro MUI_LANGUAGE "Korean"\n!insertmacro MUI_LANGUAGE "English"')
rep('        !insertmacro DemoteShortCut "$SMPROGRAMS\\$StartMenuFolder\\${APPNAME} (GPU Safe Mode).lnk"\n'
    '    !insertmacro MUI_STARTMENU_WRITE_END\n',
    '        !insertmacro DemoteShortCut "$SMPROGRAMS\\$StartMenuFolder\\${APPNAME} (GPU Safe Mode).lnk"\n'
    '    !insertmacro MUI_STARTMENU_WRITE_END\n'
    '    CreateShortCut "$DESKTOP\\${APPNAME}.lnk" "$INSTDIR\\bin\\${EXENAME}.exe" "" "$INSTDIR\\bin\\${EXENAME}.exe" 0\n')
rep('    RMDir /r /REBOOTOK "$SMPROGRAMS\\$StartMenuFolder\\"\n',
    '    RMDir /r /REBOOTOK "$SMPROGRAMS\\$StartMenuFolder\\"\n'
    '    Delete "$DESKTOP\\${APPNAME}.lnk"\n')
open(P, "w", encoding="utf-8").write(s)
print("installer: desktop shortcut, launch-after-install, Korean pages")
