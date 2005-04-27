# Microsoft Developer Studio Project File - Name="rrd" - Package Owner=<4>
# Microsoft Developer Studio Generated Build File, Format Version 6.00
# ** DO NOT EDIT **

# TARGTYPE "Win32 (x86) Static Library" 0x0104

CFG=rrd - Win32 Release
!MESSAGE This is not a valid makefile. To build this project using NMAKE,
!MESSAGE use the Export Makefile command and run
!MESSAGE 
!MESSAGE NMAKE /f "rrd.mak".
!MESSAGE 
!MESSAGE You can specify a configuration when running NMAKE
!MESSAGE by defining the macro CFG on the command line. For example:
!MESSAGE 
!MESSAGE NMAKE /f "rrd.mak" CFG="rrd - Win32 Release"
!MESSAGE 
!MESSAGE Possible choices for configuration are:
!MESSAGE 
!MESSAGE "rrd - Win32 Release" (based on "Win32 (x86) Static Library")
!MESSAGE "rrd - Win32 Debug" (based on "Win32 (x86) Static Library")
!MESSAGE 

# Begin Project
# PROP AllowPerConfigDependencies 0
# PROP Scc_ProjName ""
# PROP Scc_LocalPath ""
CPP=cl.exe
RSC=rc.exe

!IF  "$(CFG)" == "rrd - Win32 Release"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir ".\release"
# PROP BASE Intermediate_Dir ".\release"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir ".\release"
# PROP Intermediate_Dir ".\release"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:console /machine:I386
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib ..\gd1.3\release\gd.lib toolrelease\rrd.lib /nologo /subsystem:console /incremental:yes /debug /machine:I386
# ADD BASE CPP /nologo /MT /W3 /GX /O2 /D "WIN32" /D "NDEBUG" /D "_CONSOLE" /D "_MBCS" /YX /FD /c
# ADD CPP /nologo /MT /W3 /GX /O2 /I "." /I "..\gd1.3" /I "..\libpng-1.0.9" /I "..\zlib-1.1.4" /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_CTYPE_DISABLE_MACROS" /D "_MBCS" /FD /c
# SUBTRACT CPP /YX
# ADD BASE RSC /l 0x100c /d "NDEBUG"
# ADD RSC /l 0x100c /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LIB32=link.exe -lib

!ELSEIF  "$(CFG)" == "rrd - Win32 Debug"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 1
# PROP BASE Output_Dir ".\debug"
# PROP BASE Intermediate_Dir ".\debug"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 1
# PROP Output_Dir ".\debug"
# PROP Intermediate_Dir ".\debug"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:console /debug /machine:I386 /pdbtype:sept
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib ..\gd1.3\debug\gd.lib debug\rrd.lib /nologo /subsystem:console /debug /machine:I386 /pdbtype:sept
# ADD BASE CPP /nologo /MTd /W3 /Gm /GX /Zi /Od /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_MBCS" /YX /FD /c
# ADD CPP /nologo /MTd /W3 /Gm /GX /ZI /Od /I "." /I "..\gd1.3" /I "..\libpng-1.0.9" /I "..\zlib-1.1.4" /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_MBCS" /D "_CTYPE_DISABLE_MACROS" /FR /FD /c
# SUBTRACT CPP /YX
# ADD BASE RSC /l 0x100c /d "_DEBUG"
# ADD RSC /l 0x100c /d "_DEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo /o"rrdtool.bsc"
LIB32=link.exe -lib

!ENDIF 

# Begin Target

# Name "rrd - Win32 Release"
# Name "rrd - Win32 Debug"
# Begin Source File

SOURCE=..\gd1.3\gd.h
# End Source File
# Begin Source File

SOURCE=.\gdpng.c

!IF  "$(CFG)" == "rrd - Win32 Release"

# ADD CPP /nologo /GX

!ELSEIF  "$(CFG)" == "rrd - Win32 Debug"

# ADD CPP /nologo /GX /I "$(NoInherit)" /GZ

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\getopt.c
# End Source File
# Begin Source File

SOURCE=.\getopt1.c
# End Source File
# Begin Source File

SOURCE=.\gifsize.c
# End Source File
# Begin Source File

SOURCE=.\parsetime.c
# End Source File
# Begin Source File

SOURCE=.\pngsize.c

!IF  "$(CFG)" == "rrd - Win32 Release"

# ADD CPP /nologo /GX

!ELSEIF  "$(CFG)" == "rrd - Win32 Debug"

# ADD CPP /nologo /GX /I "$(NoInherit)" /GZ

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\rrd_create.c
# End Source File
# Begin Source File

SOURCE=.\rrd_diff.c
# End Source File
# Begin Source File

SOURCE=.\rrd_dump.c
# End Source File
# Begin Source File

SOURCE=.\rrd_error.c
# End Source File
# Begin Source File

SOURCE=.\rrd_fetch.c
# End Source File
# Begin Source File

SOURCE=.\rrd_format.c
# End Source File
# Begin Source File

SOURCE=.\rrd_graph.c
# End Source File
# Begin Source File

SOURCE=.\rrd_info.c
# End Source File
# Begin Source File

SOURCE=.\rrd_last.c
# End Source File
# Begin Source File

SOURCE=.\rrd_open.c
# End Source File
# Begin Source File

SOURCE=.\rrd_resize.c
# End Source File
# Begin Source File

SOURCE=.\rrd_restore.c
# End Source File
# Begin Source File

SOURCE=.\rrd_tune.c
# End Source File
# Begin Source File

SOURCE=.\rrd_update.c
# End Source File
# Begin Source File

SOURCE=.\rrd_xport.c
# End Source File
# End Target
# End Project
