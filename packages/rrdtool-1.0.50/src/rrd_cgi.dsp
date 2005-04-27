# Microsoft Developer Studio Project File - Name="rrd_cgi" - Package Owner=<4>
# Microsoft Developer Studio Generated Build File, Format Version 6.00
# ** DO NOT EDIT **

# TARGTYPE "Win32 (x86) Console Application" 0x0103

CFG=rrd_cgi - Win32 Debug
!MESSAGE This is not a valid makefile. To build this project using NMAKE,
!MESSAGE use the Export Makefile command and run
!MESSAGE 
!MESSAGE NMAKE /f "rrd_cgi.mak".
!MESSAGE 
!MESSAGE You can specify a configuration when running NMAKE
!MESSAGE by defining the macro CFG on the command line. For example:
!MESSAGE 
!MESSAGE NMAKE /f "rrd_cgi.mak" CFG="rrd_cgi - Win32 Debug"
!MESSAGE 
!MESSAGE Possible choices for configuration are:
!MESSAGE 
!MESSAGE "rrd_cgi - Win32 Debug" (based on "Win32 (x86) Console Application")
!MESSAGE "rrd_cgi - Win32 Release" (based on "Win32 (x86) Console Application")
!MESSAGE 

# Begin Project
# PROP AllowPerConfigDependencies 0
# PROP Scc_ProjName ""
# PROP Scc_LocalPath ""
CPP=cl.exe
RSC=rc.exe

!IF  "$(CFG)" == "rrd_cgi - Win32 Debug"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 1
# PROP BASE Output_Dir ".\cgi_debug"
# PROP BASE Intermediate_Dir ".\cgi_debug"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 1
# PROP Output_Dir ".\cgi_debug"
# PROP Intermediate_Dir ".\cgi_debug"
# PROP Target_Dir ""
# ADD BASE CPP /nologo /MTd /W3 /GX /ZI /Od /I "." /I "..\gd1.3" /I "..\cgilib-0.4" /I "..\zlib-1.1.4" /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_CTYPE_DISABLE_MACROS" /D "_MBCS" /FR /GZ /c
# ADD CPP /nologo /MTd /W3 /GX /ZI /Od /I "." /I "..\gd1.3" /I "..\cgilib-0.4" /I "..\zlib-1.1.4" /D "WIN32" /D "_DEBUG" /D "_CONSOLE" /D "_CTYPE_DISABLE_MACROS" /D "_MBCS" /FR /GZ /c
# ADD BASE RSC /l 0x409 /d "_DEBUG"
# ADD RSC /l 0x409 /d "_DEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib odbc32.lib odbccp32.lib ..\gd1.3\debug\gd.lib debug\rrd.lib ..\cgilib-0.4\debug\cgilib.lib ..\zlib-1.1.4\Debug\zlib.lib ..\libpng-1.0.9\Debug\png.lib /nologo /subsystem:console /debug /machine:I386 /pdbtype:sept
# SUBTRACT BASE LINK32 /pdb:none
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib odbc32.lib odbccp32.lib ..\gd1.3\debug\gd.lib debug\rrd.lib ..\cgilib-0.4\debug\cgilib.lib ..\zlib-1.1.4\Debug\zlib.lib ..\libpng-1.0.9\Debug\png.lib /nologo /subsystem:console /debug /machine:I386 /pdbtype:sept
# SUBTRACT LINK32 /pdb:none

!ELSEIF  "$(CFG)" == "rrd_cgi - Win32 Release"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir ".\cgi_release"
# PROP BASE Intermediate_Dir ".\cgi_release"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir ".\cgi_release"
# PROP Intermediate_Dir ".\cgi_release"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
# ADD BASE CPP /nologo /MT /W3 /GX /O2 /I "." /I "..\gd1.3" /I "..\cgilib-0.4" /I "..\zlib-1.1.4" /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_CTYPE_DISABLE_MACROS" /D "_MBCS" /c
# ADD CPP /nologo /MT /W3 /GX /O2 /I "." /I "..\gd1.3" /I "..\cgilib-0.4" /I "..\zlib-1.1.4" /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_CTYPE_DISABLE_MACROS" /D "_MBCS" /c
# ADD BASE RSC /l 0x409 /d "NDEBUG"
# ADD RSC /l 0x409 /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib ..\gd1.3\release\gd.lib release\rrd.lib ..\cgilib-0.4\release\cgilib.lib ..\zlib-1.1.4\Release\zlib.lib ..\libpng-1.0.9\Release\png.lib /nologo /subsystem:console /machine:I386 /pdbtype:sept
# SUBTRACT BASE LINK32 /pdb:none
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:console /machine:I386 /pdbtype:sept
# SUBTRACT LINK32 /pdb:none

!ENDIF 

# Begin Target

# Name "rrd_cgi - Win32 Debug"
# Name "rrd_cgi - Win32 Release"
# Begin Group "Source Files"

# PROP Default_Filter "cpp;c;cxx;rc;def;r;odl;idl;hpj;bat"
# Begin Source File

SOURCE=.\rrd_cgi.c
DEP_CPP_RRD_C=\
	"..\cgilib-0.4\cgi.h"\
	"..\gd1.3\gd.h"\
	".\config_aux.h"\
	".\getopt.h"\
	".\ntconfig.h"\
	".\rrd.h"\
	".\rrd_format.h"\
	".\rrd_tool.h"\
	
# End Source File
# End Group
# Begin Group "Header Files"

# PROP Default_Filter "h;hpp;hxx;hm;inl"
# End Group
# Begin Group "Resource Files"

# PROP Default_Filter "ico;cur;bmp;dlg;rc2;rct;bin;rgs;gif;jpg;jpeg;jpe"
# End Group
# End Target
# End Project
